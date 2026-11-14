import UIKit
import UniformTypeIdentifiers
import MeadowBattleSupport
import MeadowWorldSupport
import ClassroomGameCore

/// Configure a map, inspect its scenery, or create/resume a persistent expedition.
final class MeadowMapSettingsViewController: UIViewController {
    var classroomGenerated:((MeadowMapConfiguration)throws->GeneratedMeadowMap)?
    var classroomCampaignReady:((MeadowCampaignSession)->Void)?
    var classroomSettingsClosed:(()->Void)?
    override func viewDidDisappear(_ animated:Bool){super.viewDidDisappear(animated);classroomSettingsClosed?()}
    private let fields = ["总节点数","普通战斗","Boss","奖励","空地点","额外道路","随机种子"]
    private var inputs: [UITextField] = []
    private var sliders: [UISlider] = []
    private var lastValid = MeadowMapConfiguration()
    private let status = UILabel()
    private let encounters = UILabel()
    private let generateButton = UIButton(type:.system)
    private let enterButton = UIButton(type:.system)
    private let preview = MeadowMapThumbnail()
    private let startCampaignButton=UIButton(type:.system)

    private let campaignClass=UISegmentedControl(items:["冒险者","游侠","魔剑士","龙骑士"])
    private let companionClass=UISegmentedControl(items:["冒险者","游侠","魔剑士","龙骑士"])
    private let classSummaries=(0..<6).map{_ in UILabel()}
    private let extraClasses=(0..<4).map{_ in UISegmentedControl(items:["冒险者","游侠","魔剑士","龙骑士"])}
    private let studentCount=UIStepper()
    private let studentCountLabel=UILabel()
    private var classRows:[UIStackView]=[]
    private var studentNames:[UITextField]=[]
    private var profileLooks:[String:PlayerAppearance]=[:]
    private var classControls:[UISegmentedControl] {[campaignClass,companionClass]+extraClasses}
    private var result: GeneratedMeadowMap?
    private var revision = 0
    private let gold = UIColor(red:0.91,green:0.77,blue:0.43,alpha:1)

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red:0.055,green:0.09,blue:0.065,alpha:1);MeadowGlassBackdrop.install(in:view)
        let scroll=UIScrollView(), rightScroll=UIScrollView(), form=UIStackView(), right=UIStackView()
        form.axis = .vertical; form.spacing=10; right.axis = .vertical; right.spacing=12
        let title=UILabel();title.text="随机林地";title.font = .boldSystemFont(ofSize:26);title.textColor=gold
        form.addArrangedSubview(title)
        let defaults=["10","4","1","3","1","1","31827"]
        for (index,name) in fields.enumerated() {
            let row=UIStackView();row.spacing=8;row.alignment = .center
            let label=UILabel();label.text=name;label.font = .boldSystemFont(ofSize:17);label.textColor = .white
            label.widthAnchor.constraint(equalToConstant:90).isActive=true
            let field=UITextField();field.text=defaults[index];field.tag=index
            field.font = .monospacedDigitSystemFont(ofSize:19,weight:.semibold);field.textColor=gold
            field.backgroundColor=UIColor(white:1,alpha:0.07);field.borderStyle = .roundedRect
            field.keyboardType = .numberPad;field.accessibilityLabel=name
            field.addTarget(self,action:#selector(inputChanged(_:)),for:.editingChanged)
            inputs.append(field);row.addArrangedSubview(label);row.addArrangedSubview(field)
            row.heightAnchor.constraint(equalToConstant:40).isActive=true
            form.addArrangedSubview(row)
            if index<6 {
                let slider=UISlider();slider.tag=index;slider.minimumValue=index==0 ? 4:0
                slider.maximumValue=index==0 ? 30:index==5 ? Float(MeadowMapGenerator.maximumExtraRoads(total:10)):9
                slider.value=Float(defaults[index]) ?? 0;slider.minimumTrackTintColor=gold;slider.isContinuous=true
                slider.accessibilityLabel=name+"滑块"
                slider.addTarget(self,action:#selector(slid(_:)),for:.valueChanged)
                sliders.append(slider);form.addArrangedSubview(slider)
            }
        }
        let fixed=UILabel();fixed.text="起点固定 1 · 总数与各分类自动匹配";fixed.textColor=gold;fixed.font = .boldSystemFont(ofSize:15)
        fixed.numberOfLines=0;form.addArrangedSubview(fixed)
        let suggest=button("恢复建议分配",action:#selector(suggested));form.addArrangedSubview(suggest)
        let seed=button("换个种子",action:#selector(newSeed));form.addArrangedSubview(seed)
        let close=button("返回原地图",action:#selector(close));form.addArrangedSubview(close)
        let heading=UILabel();heading.text="建筑与道路预览";heading.font = .boldSystemFont(ofSize:22);heading.textColor=gold
        let note=UILabel();note.text="生成地图后开始1—6名学生的行程；逐人选择职业，默认同队，进入后可调整分组。"
        note.font = .systemFont(ofSize:17,weight:.medium);note.textColor = .white;note.numberOfLines=0
        status.textColor=gold;status.numberOfLines=0;status.font = .boldSystemFont(ofSize:17)
        encounters.textColor = .white;encounters.numberOfLines=0;encounters.font = .systemFont(ofSize:16,weight:.semibold)
        generateButton.configuration=button("生成道路预览",action:#selector(generate)).configuration
        generateButton.addTarget(self,action:#selector(generate),for:.touchUpInside)
        enterButton.configuration=button("进入林地预览",action:#selector(enter)).configuration
        enterButton.addTarget(self,action:#selector(enter),for:.touchUpInside)
        right.addArrangedSubview(heading);right.addArrangedSubview(note);right.addArrangedSubview(preview)
        right.addArrangedSubview(status);right.addArrangedSubview(generateButton);if classroomCampaignReady == nil {right.addArrangedSubview(enterButton)}
        startCampaignButton.configuration=button("开始新行程",action:#selector(startCampaign)).configuration
        startCampaignButton.addTarget(self,action:#selector(startCampaign),for:.touchUpInside)
        studentCount.minimumValue=1;studentCount.maximumValue=6;studentCount.value=2
        studentCount.addTarget(self,action:#selector(refreshPartySummary),for:.valueChanged)
        let countRow=UIStackView(arrangedSubviews:[studentCountLabel,studentCount]);countRow.distribution = .equalSpacing
        studentCountLabel.textColor=gold;right.addArrangedSubview(countRow)
        for (i,selector) in classControls.enumerated() {
            let label=UILabel();label.text="P\(i+1)职业";label.font = .boldSystemFont(ofSize:17);label.textColor=gold
            selector.accessibilityLabel="P\(i+1)职业"
            selector.selectedSegmentIndex=i==0 ? 2:1
            selector.setTitleTextAttributes([.foregroundColor:UIColor.white,.font:UIFont.boldSystemFont(ofSize:16)],for:.normal)
            selector.setTitleTextAttributes([.foregroundColor:UIColor.white],for:.selected)
            selector.selectedSegmentTintColor=UIColor(red:0.35,green:0.35,blue:0.15,alpha:1)
            selector.heightAnchor.constraint(equalToConstant:44).isActive=true
            selector.addTarget(self,action:#selector(refreshPartySummary),for:.valueChanged)
            let summary=classSummaries[i];summary.numberOfLines=0;summary.textColor = .white;summary.font = .systemFont(ofSize:16,weight:.semibold)
            let name=UITextField();name.placeholder="学生姓名（可选）";name.borderStyle = .roundedRect;name.textColor = .white;name.backgroundColor=UIColor(white:1,alpha:0.08);studentNames.append(name)
            let profiles=UIButton(type:.system);profiles.setTitle("读取人物档案",for:.normal);profiles.showsMenuAsPrimaryAction=true
            // Only the used slots (of 50) are offered.
            profiles.menu=UIMenu(children:(1...MeadowSlotStore.profileCount).compactMap{slot in
                guard let found=try? MeadowTeacherCoordinator.slotStore.profile(slot) else{return nil}
                let entry:MeadowSaveSlot<MeadowPlayerProfile>=found
                return UIAction(title:"人物槽\(slot) · \(entry.value.name)"){[weak self] _ in
                    guard let self else{return};name.text=entry.value.name;self.profileLooks["p\(i+1)"]=entry.value.appearance
                    profiles.setTitle("已选："+entry.value.name,for:.normal)
                }
            })
            let row=UIStackView(arrangedSubviews:[label,name,profiles,selector,summary]);row.axis = .vertical;row.spacing=6
            classRows.append(row);right.addArrangedSubview(row)
        }
        refreshPartySummary()
        // Optional question bank: roadside-find events become quiz events (format: docs/question-bank-format.md).
        var quizStyle=UIButton.Configuration.gray();quizStyle.image=UIImage(systemName:"questionmark.bubble.fill");quizStyle.imagePadding=8
        quizStyle.title="导入题库";quizStyle.baseForegroundColor=gold;quizStyle.cornerStyle = .capsule
        quizButton.configuration=quizStyle
        quizButton.addAction(UIAction{[weak self] _ in self?.importQuizBank()},for:.touchUpInside)
        quizClear.setImage(UIImage(systemName:"xmark.circle.fill"),for:.normal);quizClear.tintColor=UIColor.white.withAlphaComponent(0.5)
        quizClear.addAction(UIAction{[weak self] _ in self?.quizBank=nil;self?.refreshQuizLabel()},for:.touchUpInside)
        quizLabel.font = .systemFont(ofSize:15,weight:.semibold);quizLabel.textColor=UIColor.white.withAlphaComponent(0.7);quizLabel.numberOfLines=2
        let quizRow=UIStackView(arrangedSubviews:[quizButton,quizLabel,quizClear]);quizRow.spacing=10;quizRow.alignment = .center
        right.addArrangedSubview(quizRow);refreshQuizLabel()
        right.addArrangedSubview(startCampaignButton)
        right.addArrangedSubview(button("继续已保存行程",action:#selector(continueCampaign)))
        right.addArrangedSubview(button("历史结算",action:#selector(showCompletedCampaigns)))
        right.addArrangedSubview(button("怪物动作检视",action:#selector(showMonsterGallery)))
        right.addArrangedSubview(encounters)
        preview.heightAnchor.constraint(equalToConstant:200).isActive=true
        scroll.addSubview(form);rightScroll.addSubview(right);view.addSubview(scroll);view.addSubview(rightScroll)
        for v in [scroll,rightScroll,form,right] { v.translatesAutoresizingMaskIntoConstraints=false }
        let guide=view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:guide.leadingAnchor,constant:18),scroll.topAnchor.constraint(equalTo:guide.topAnchor,constant:14),
            scroll.bottomAnchor.constraint(equalTo:guide.bottomAnchor,constant:-14),scroll.widthAnchor.constraint(equalTo:guide.widthAnchor,multiplier:0.39),
            form.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor),form.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor),
            form.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor),form.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor),
            form.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor),
            rightScroll.leadingAnchor.constraint(equalTo:scroll.trailingAnchor,constant:22),rightScroll.trailingAnchor.constraint(equalTo:guide.trailingAnchor,constant:-18),
            rightScroll.topAnchor.constraint(equalTo:guide.topAnchor,constant:16),rightScroll.bottomAnchor.constraint(equalTo:guide.bottomAnchor,constant:-14),
            right.leadingAnchor.constraint(equalTo:rightScroll.contentLayoutGuide.leadingAnchor),right.trailingAnchor.constraint(equalTo:rightScroll.contentLayoutGuide.trailingAnchor),
            right.topAnchor.constraint(equalTo:rightScroll.contentLayoutGuide.topAnchor),right.bottomAnchor.constraint(equalTo:rightScroll.contentLayoutGuide.bottomAnchor),
            right.widthAnchor.constraint(equalTo:rightScroll.frameLayoutGuide.widthAnchor)
        ])
        changed()
    }
    private let quizButton=UIButton(type:.system),quizLabel=UILabel(),quizClear=UIButton(type:.system)
    private var quizBank:[QuizQuestion]?
    private func refreshQuizLabel(){
        if let bank=quizBank,!bank.isEmpty {quizLabel.text="✓ \(bank.count) 题 · 路边事件改为答题";quizLabel.textColor=gold;quizClear.isHidden=false}
        else {quizLabel.text="可选 · 不导入则保持原随机事件";quizLabel.textColor=UIColor.white.withAlphaComponent(0.6);quizClear.isHidden=true}
    }
    private func importQuizBank(){
        DocumentImportPresenter.shared.present(types:[.plainText,.utf8PlainText,.json,.text]){[weak self] url in
            guard let self,let url else{return}
            do{
                let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
                self.quizBank=try QuizBankParser.parse(Data(contentsOf:url));self.refreshQuizLabel()
            }catch{
                let alert=UIAlertController(title:"题库没有导入",message:error.localizedDescription,preferredStyle:.alert)
                alert.addAction(UIAlertAction(title:"好",style:.default));self.present(alert,animated:true)
            }
        }
    }
    private func button(_ title:String,action:Selector) -> UIButton {
        let b=UIButton(type:.system);var c=UIButton.Configuration.filled();c.title=title
        c.baseBackgroundColor=gold;c.baseForegroundColor=UIColor(red:0.12,green:0.17,blue:0.12,alpha:1)
        c.contentInsets=NSDirectionalEdgeInsets(top:9,leading:10,bottom:9,trailing:10);b.configuration=c
        b.addTarget(self,action:action,for:.touchUpInside);return b
    }
    private func configuration() throws -> MeadowMapConfiguration {
        guard let total=Int(inputs[0].text ?? ""),let combat=Int(inputs[1].text ?? ""),let boss=Int(inputs[2].text ?? ""),
              let reward=Int(inputs[3].text ?? ""),let empty=Int(inputs[4].text ?? ""),let roads=Int(inputs[5].text ?? ""),
              let seed=UInt64(inputs[6].text ?? "") else { throw NSError(domain:"地图",code:1,userInfo:[NSLocalizedDescriptionKey:"请输入完整的非负整数。总数范围4—30。种子为0—18446744073709551615。"]) }
        var c=MeadowMapConfiguration();c.total=total;c.combat=combat;c.boss=boss;c.reward=reward;c.empty=empty;c.extraRoads=roads;c.seed=seed
        try c.validate();return c
    }
    private func applyCounts(_ c: MeadowMapConfiguration) {
        inputs[0].text=String(c.total)
        for (index,value) in [c.combat,c.boss,c.reward,c.empty].enumerated() { inputs[index+1].text=String(value) }
        inputs[5].text=String(c.extraRoads)
        lastValid=c
    }
    @objc private func inputChanged(_ field: UITextField) {
        if let value=Int(field.text ?? "") {
            if field.tag==0,let c=try? lastValid.changingTotal(to:value) { applyCounts(c) }
            else if (1...4).contains(field.tag),value>=0,let c=try? lastValid.changingCount(field:field.tag-1,to:value) { applyCounts(c) }
        }
        changed()
    }
    @objc private func slid(_ slider: UISlider) {
        let value=Int(slider.value.rounded());slider.value=Float(value)
        inputs[slider.tag].text=String(value)
        inputChanged(inputs[slider.tag])
    }
    private func changed() {
        revision+=1;result=nil;preview.map=nil;encounters.text=nil;enterButton.isEnabled=false;startCampaignButton.isEnabled=false
        do {
            let c=try configuration();lastValid=c
            for slider in sliders {
                slider.maximumValue=slider.tag==0 ? 30:slider.tag==5 ? Float(MeadowMapGenerator.maximumExtraRoads(total:c.total)):Float(c.total-1)
                slider.value=Float(inputs[slider.tag].text ?? "") ?? 0
            }
            status.text="起点1 + 战斗\(c.combat) + Boss\(c.boss) + 奖励\(c.reward) + 空地\(c.empty) = \(c.total)\n数量正确，可生成。"
            generateButton.isEnabled=true
        } catch {
            var detail=error.localizedDescription
            let numbers=inputs.prefix(5).compactMap{Int($0.text ?? "")}
            if numbers.count==5,numbers.allSatisfy({(0...30).contains($0)}) {
                let allocated=1+numbers.dropFirst().reduce(0,+),difference=numbers[0]-allocated
                if difference != 0 { detail="已分配 \(allocated) / 总数 \(numbers[0])，"+(difference>0 ? "还差 \(difference) 个。" : "超出 \(-difference) 个。")+"\n"+detail }
            }
            status.text=detail;generateButton.isEnabled=false
        }
    }
    @objc private func suggested() {
        guard let n=Int(inputs[0].text ?? ""),(4...30).contains(n) else { changed();return }
        if let c=try? lastValid.changingTotal(to:n) { applyCounts(c) }
        changed()
    }
    @objc private func newSeed() { inputs[6].text=String(UInt64.random(in:0...UInt64.max));changed() }
    @objc private func generate() {
        view.endEditing(true)
        guard let config=try? configuration() else { changed();return }
        let token=revision;generateButton.isEnabled=false;status.text="正在生成林地…"
        let factory=classroomGenerated
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let output=Result { () throws -> (GeneratedMeadowMap,String) in
                let map=try factory?(config) ?? MeadowMapGenerator.generate(config)
                return (map,try MeadowEncounterPlanner.summary(map,catalog:MeadowCampaignSession.catalog())+"\n\n"+MeadowCampaignSession.siteSummary(layout:map))
            }
            DispatchQueue.main.async {
                guard let self,self.revision==token else { return }
                self.generateButton.isEnabled=true
                switch output {
                case .success(let (map,summary)):
                    self.result=map;self.preview.map=map;self.enterButton.isEnabled=true;self.startCampaignButton.isEnabled=true
                    self.encounters.text=summary
                    self.status.text="\(map.map.nodes.count)个节点 · \(map.roads.count)条道路 · \(config.extraRoads)条环路\n种子 \(config.seed)"
                case .failure(let error): self.status.text=error.localizedDescription
                }
            }
        }
    }
    static func campaignStore()->MeadowCampaignStore {
        let base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        return MeadowCampaignStore(url:base.appendingPathComponent("ClassroomMeadow/campaign-v1.json"))
    }
    private var partyConfiguration:MeadowPartyConfiguration {
        let ids=MeadowPartyConfiguration.classIDs
        func selected(_ control:UISegmentedControl,_ fallback:String)->String {
            ids.indices.contains(control.selectedSegmentIndex) ? ids[control.selectedSegmentIndex]:fallback
        }
        return .init(playerClassID:selected(campaignClass,"spellblade"),companionClassID:selected(companionClass,"ranger"))
    }
    @objc private func refreshPartySummary() {
        do {
            let catalog=try MeadowCampaignSession.catalog(),config=partyConfiguration
            studentCountLabel.text="学生人数：\(Int(studentCount.value)) / 6"
            for (i,control) in classControls.enumerated(){classRows[i].isHidden=i>=Int(studentCount.value);classSummaries[i].text=try MeadowPartyConfiguration.summary(for:MeadowPartyConfiguration.classIDs[max(0,control.selectedSegmentIndex)],catalog:catalog)}
        }catch{for label in classSummaries{label.text="职业信息读取失败："+error.localizedDescription}}
    }
    @objc private func startCampaign() {
        guard let result else{return}
        let config=partyConfiguration
        let create={ [weak self] in
            guard let self else{return}
            do {
                let store=Self.campaignStore(),base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
                if let old=try store.read(){try MeadowTeacherCoordinator.slotStore.backup(old)}
                let campStore=CampSaveStore(url:base.appendingPathComponent("MeadowCamp/camp-v1.json"))
                var units:[String:ClassroomGameCore.GameUnit]?,appearance="forester"
                if let bytes=try campStore.read() {
                    let save=try JSONDecoder().decode(CampSave.self,from:bytes)
                    try save.validate(appearances:["forester","wayfarer"],equipment:Set(["trainingSword","huntingBow","greatSword","legendaryStaff","leatherArmor","runeArmor","powerBadge","actionRing"]))
                    units=save.archive.state.units;appearance=save.appearanceID
                }
                try store.preserveCompletedCampaign()
                let session=try MeadowCampaignSession.new(layout:result,appearanceID:appearance,playerClassID:config.playerClassID,companionClassID:config.companionClassID,studentClasses:Array(self.classControls.prefix(Int(self.studentCount.value))).map{MeadowPartyConfiguration.classIDs[max(0,$0.selectedSegmentIndex)]},studentNames:self.studentNames.prefix(Int(self.studentCount.value)).map{$0.text ?? ""},playerAppearances:self.profileLooks,loadouts:units,difficulty:GameDifficulty.lastChosen,quizBank:self.quizBank,persist:store.write)
                self.presentCampaign(session)
            } catch {self.status.text="未开始新行程："+error.localizedDescription}
        }
        if FileManager.default.fileExists(atPath:Self.campaignStore().url.path) {
            let alert=UIAlertController(title:"开始新行程？",message:"当前行程会先自动备份，手动行程槽保留。营地衣装与装备存档会保留。\n"+[classSummaries[0].text,classSummaries[1].text].compactMap{$0}.joined(separator:"\n\n"),preferredStyle:.alert)
            alert.addAction(UIAlertAction(title:"取消",style:.cancel))
            alert.addAction(UIAlertAction(title:"开始新行程",style:.destructive,handler:{_ in create()}));present(alert,animated:true)
        } else {create()}
    }
    @objc private func continueCampaign() {
        do {
            let store=Self.campaignStore()
            guard let save=try store.read() else{status.text="还没有已保存行程。先生成地图并开始新行程。";return}
            presentCampaign(try MeadowCampaignSession(save:save,persist:store.write))
        } catch {status.text="无法读取行程，原存档已保留："+error.localizedDescription}
    }
    @objc private func showMonsterGallery(){present(MeadowMonsterGalleryController(),animated:true)}
    @objc private func showCompletedCampaigns(){
        do{
            let history=try Self.campaignStore().completedHistory(),saves=history.saves
            guard !saves.isEmpty else{status.text="还没有可读取的已结算行程。"+history.notice;return}
            let menu=UIAlertController(title:"历史结算",message:"选择行程查看已保存结果。\n"+history.notice,preferredStyle:.actionSheet)
            let format=DateFormatter();format.dateFormat="MM-dd HH:mm"
            for save in saves {
                guard let result=save.completion else{continue}
                menu.addAction(UIAlertAction(title:format.string(from:result.completedAt)+" · "+(result.outcome=="victory" ? "通关":"队伍倒地")+" · 种子\(save.layout.configuration.seed)",style:.default){[weak self] _ in
                    let screen=MeadowCampaignResultsViewController(result:result,catalog:save.archive.catalog,seed:save.layout.configuration.seed);guard let self else{return}
                    if let alert=self.presentedViewController as? UIAlertController{alert.dismiss(animated:true){self.present(screen,animated:true)}}else{self.present(screen,animated:true)}
                })
            }
            menu.addAction(UIAlertAction(title:"取消",style:.cancel));menu.popoverPresentationController?.sourceView=preview;menu.popoverPresentationController?.sourceRect=preview.bounds;present(menu,animated:true)
        }catch{status.text="历史结算读取失败，原文件已保留："+error.localizedDescription}
    }
    private func presentCampaign(_ session:MeadowCampaignSession) {
        if let classroomCampaignReady {classroomCampaignReady(session);dismiss(animated:true);return}
        let controller=GameViewController(campaign:session);controller.modalPresentationStyle = .fullScreen
        present(controller,animated:true)
    }
    @objc private func enter() {
        guard let result else { return }
        let controller=GameViewController(previewMap:result);controller.modalPresentationStyle = .fullScreen
        present(controller,animated:true)
    }
    @objc private func close() { dismiss(animated:true) }
}

private final class MeadowMapThumbnail: UIView {
    var map: GeneratedMeadowMap? { didSet { setNeedsDisplay() } }
    override func draw(_ rect:CGRect) {
        UIColor(red:0.1,green:0.19,blue:0.13,alpha:1).setFill();UIBezierPath(roundedRect:bounds,cornerRadius:12).fill()
        guard let map else { return }
        let scale=min((bounds.width-24)/1280,(bounds.height-24)/CGFloat(map.coordinateHeight))
        func point(_ x:Double,_ y:Double) -> CGPoint { CGPoint(x:bounds.midX+CGFloat(x-640)*scale,y:bounds.midY+CGFloat(y-map.coordinateHeight/2)*scale) }
        UIColor(red:0.6,green:0.52,blue:0.32,alpha:1).setStroke()
        for road in map.roads {
            let path=UIBezierPath();path.lineWidth=3;path.move(to:point(road.points[0].x,road.points[0].y))
            for p in road.points.dropFirst() { path.addLine(to:point(p.x,p.y)) };path.stroke()
        }
        let colors:[String:UIColor]=["start":.systemYellow,"combat":.systemRed,"boss":.systemPurple,"reward":.systemGreen,"empty":.lightGray]
        let names=["start":"起","combat":"战","boss":"首","reward":"奖","empty":"空"]
        for prop in map.props.filter({$0.nodeID != nil}).sorted(by:{$0.y<$1.y}) {
            let p=point(prop.x,prop.y),width=CGFloat(prop.width)*scale
            if let image=UIImage(named:prop.asset) {
                let height=width*image.size.height/image.size.width,anchor:CGFloat=prop.asset=="CampTent" ? 0.10:0.08
                image.draw(in:CGRect(x:p.x-width/2,y:p.y-height*(1-anchor),width:width,height:height))
            }
            guard let node=map.map.nodes.first(where:{$0.id==prop.nodeID}) else { continue }
            let badge=point(prop.x,prop.y-Double(SceneDefinition.landmarkBadgeRise(asset:prop.asset,width:CGFloat(prop.width)))),r:CGFloat=5
            colors[node.kind.rawValue]?.setFill();UIBezierPath(ovalIn:CGRect(x:badge.x-r,y:badge.y-r,width:r*2,height:r*2)).fill()
            let text=names[node.kind.rawValue] ?? "?"
            (text as NSString).draw(in:CGRect(x:badge.x-4,y:badge.y-5,width:10,height:11),withAttributes:[.font:UIFont.boldSystemFont(ofSize:8),.foregroundColor:UIColor.black])
        }
    }
}

final class MeadowCampaignResultsViewController:UIViewController {
    let result:MeadowCampaignCompletion,catalog:GameCatalog,seed:UInt64
    var onReturnSettings:(()->Void)?
    private let scroll=UIScrollView(),stack=UIStackView()
    private let close=MeadowPreviewPalette.button("返回查看"),settings=MeadowPreviewPalette.button("保存并返回设置")
    init(result:MeadowCampaignCompletion,catalog:GameCatalog,seed:UInt64){self.result=result;self.catalog=catalog;self.seed=seed;super.init(nibName:nil,bundle:nil);modalPresentationStyle = .fullScreen;isModalInPresentation=true}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override var prefersStatusBarHidden:Bool{true}
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask{.landscape}
    override func viewDidLoad(){
        super.viewDidLoad();view.backgroundColor=MeadowPreviewPalette.panel
        view.addSubview(scroll);scroll.addSubview(stack);view.addSubview(close);view.addSubview(settings)
        stack.axis = .vertical;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:12),stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-12),stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor,constant:-16),stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor,constant:-32)])
        func text(_ value:String,_ size:CGFloat=18){let label=MeadowPreviewPalette.label(value,size:size);label.numberOfLines=0;stack.addArrangedSubview(label)}
        text(result.outcome=="victory" ? "行程完成":"行程结束 · 队伍倒地",30)
        let date=DateFormatter();date.dateStyle = .medium;date.timeStyle = .short
        text(date.string(from:result.completedAt)+" · 地图种子 \(seed)",16)
        text("探索 \(result.exploredNodes)/\(result.totalNodes) 地点  ·  清理 \(result.clearedEncounters)/\(result.totalEncounters) 战斗地点  ·  补给 \(result.collectedRewards)/\(result.totalRewards)")
        text("累计移动 \(Int(result.distance.rounded())) 距离  ·  移动购买花费 \(result.movementCoins) 金币")
        for player in result.players {
            let attributes=(try? GameRules.attributes(player,catalog:catalog)) ?? player.baseAttributes
            text(player.name,23)
            let health=MeadowBattleResourceBar();health.show("生命",value:player.health,maximum:attributes.maximumHealth,color:.systemGreen);health.heightAnchor.constraint(equalToConstant:44).isActive=true;stack.addArrangedSubview(health)
            text("持有金币 \(player.coins)  ·  积分 \(player.score)")
            text("结束时个人行动 \(player.ap) · 护盾 \(player.shield) · "+(player.isAlive ? "存活":"倒地"),17)
            let equipment=player.equipment.itemIDs.map{(try? catalog.item($0).name) ?? $0}.joined(separator:"、")
            text("装备："+(equipment.isEmpty ? "未装备":equipment),17)
            let items=player.inventory.keys.sorted().map{((try? catalog.item($0).name) ?? $0)+" ×\(player.inventory[$0]!)"}.joined(separator:"、")
            text("行囊："+(items.isEmpty ? "空":items),17)
        }
        text("以上为已保存的最终结果，金币和物品已经按行程中的实际操作结算。",16)
        close.addAction(UIAction{[weak self] _ in self?.dismiss(animated:true)},for:.touchUpInside)
        settings.isHidden=onReturnSettings==nil
        settings.addAction(UIAction{[weak self] _ in guard let self else{return};self.dismiss(animated:true){self.onReturnSettings?()}},for:.touchUpInside)
    }
    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews();let inset=view.safeAreaInsets,left=max(16,inset.left+12),right=view.bounds.width-max(16,inset.right+12),bottom=view.bounds.height-max(12,inset.bottom+8)
        scroll.frame=CGRect(x:left,y:max(10,inset.top+8),width:right-left,height:max(1,bottom-74-max(10,inset.top+8)))
        let width=(right-left-12)/2
        close.frame=CGRect(x:left,y:bottom-52,width:onReturnSettings==nil ? right-left:width,height:44);settings.frame=CGRect(x:left+width+12,y:bottom-52,width:width,height:44)
    }
}


/// A separate art inspection screen, never attached to the saved rule engine.
private final class MeadowMonsterGalleryController:UIViewController {
    private let gallery=MeadowMonsterGalleryView(),pick=UISegmentedControl(items:["史莱姆","森林狼","弓手","石像","巨魔","魔龙"])
    private let titleLabel=MeadowPreviewPalette.label("怪物动作检视",size:26,weight:.heavy)
    private let phase=MeadowPreviewPalette.label("",size:19,weight:.bold)
    private let close=MeadowPreviewPalette.button("返回"),replay=MeadowPreviewPalette.button("重播动作")
    init(){super.init(nibName:nil,bundle:nil);modalPresentationStyle = .fullScreen}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override var prefersStatusBarHidden:Bool{true}
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask{.landscape}
    override func viewDidLoad(){
        super.viewDidLoad();view.backgroundColor=MeadowPreviewPalette.panel
        for v in [gallery,pick,titleLabel,phase,close,replay]{view.addSubview(v)}
        phase.numberOfLines=2;phase.font=MeadowPreviewPalette.font(17)
        pick.selectedSegmentIndex=0;pick.selectedSegmentTintColor=MeadowPreviewPalette.gold
        pick.setTitleTextAttributes([.foregroundColor:MeadowPreviewPalette.panel,.font:MeadowPreviewPalette.font(18)],for:.selected)
        pick.setTitleTextAttributes([.foregroundColor:UIColor.white,.font:MeadowPreviewPalette.font(18)],for:.normal)
        pick.addAction(UIAction{[weak self] _ in guard let self else{return};self.gallery.select(MonsterVisualSpec.ids[self.pick.selectedSegmentIndex])},for:.valueChanged)
        gallery.onPhase={ [weak self] value in self?.phase.text=value+" · 仅外观检视，不消耗行程资源" }
        close.addAction(UIAction{[weak self] _ in self?.dismiss(animated:true)},for:.touchUpInside)
        replay.addAction(UIAction{[weak self] _ in guard let self else{return};self.gallery.select(MonsterVisualSpec.ids[self.pick.selectedSegmentIndex])},for:.touchUpInside)
    }
    override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);gallery.start()}
    override func viewWillDisappear(_ animated:Bool){super.viewWillDisappear(animated);gallery.stop()}
    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews();let safe=view.safeAreaInsets,left=max(16,safe.left+8),right=view.bounds.width-max(16,safe.right+8),width=right-left,top=max(12,safe.top+8),bottom=view.bounds.height-max(12,safe.bottom+8)
        titleLabel.frame=CGRect(x:left,y:top,width:250,height:36);close.frame=CGRect(x:right-90,y:top,width:90,height:38)
        pick.frame=CGRect(x:left,y:top+46,width:width,height:42)
        gallery.frame=CGRect(x:left,y:top+98,width:width,height:max(1,bottom-top-156))
        phase.frame=CGRect(x:left,y:bottom-44,width:width-150,height:40);replay.frame=CGRect(x:right-140,y:bottom-44,width:140,height:40)
    }
}
private final class MeadowMonsterGalleryView:UIView {
    var onPhase:((String)->Void)?
    private let world=UIView(),monster=UIImageView(),hero=MeadowBattleActorView(frame:.zero)
    private let grounding=MeadowBattleGroundingView(image:nil,soleY:240,contacts:[])
    private let heroGrounding=MeadowBattleGroundingView(image:nil,soleY:214,contacts:[])
    private let missile=CAShapeLayer()
    private var heroGrounded=false
    private let clock=MeadowBattleSceneClock()
    private var species="slime",time=0.0,key=""
    override init(frame:CGRect){
        super.init(frame:frame);clipsToBounds=true;layer.cornerRadius=12;backgroundColor=MeadowPreviewPalette.panel
        world.bounds=CGRect(x:0,y:0,width:1000,height:600);addSubview(world)
        for (i,name) in MeadowBattleCanvasGeometry.sceneLayerOrder.enumerated(){
            let image=UIImageView(image:MeadowBattlePlateProcessor.image(named:name,role:[.farForest,.ground,.midground,.foreground][i]));image.frame=CGRect(x:0,y:-159,width:1000,height:1000*1201/1309);image.layer.zPosition=i==3 ? 900:CGFloat(-100+i);world.addSubview(image)
        }
        world.addSubview(grounding);world.addSubview(heroGrounding);world.addSubview(hero);world.addSubview(monster);world.layer.addSublayer(missile);missile.zPosition=800;missile.lineWidth=3;missile.fillColor=nil;monster.layer.magnificationFilter = .nearest
        hero.setWeaponAsset(HeroFrames.weaponVisual("trainingSword")?.battleAsset)
        clock.onTick={ [weak self] delta in guard let self else{return};self.time+=delta;if self.time>6.4{self.time=0};self.render() }
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    func select(_ id:String){species=id;time=0;key="";MeadowMonsterFrames.retain([id]);render()}
    func start(){select(species);clock.start()}
    func stop(){clock.stop();MeadowMonsterFrames.retain([])}
    private func render(){
        guard let spec=MonsterVisualSpec.find(species) else{return}
        CATransaction.begin();CATransaction.setDisableActions(true);defer{CATransaction.commit()}
        let attack=time>=0.8 && time<1.9 ? time-0.8:nil,hurt=time>=2.4 && time<2.8 ? time-2.4:nil,cast=time>=3.2 && time<4.6 ? time-3.2:nil,death=time>=5 ? time-5:nil
        let intent=PartyIntent(id:"gallery",action:.attack,actor:"m1",target:"p1",targets:["p1"],command:.monsterStep,enemy:true,weaponID:nil,monsterTemplateID:species,enemyRanged:spec.ranged)
        let shift=PartyVisual.travel(attack != nil ? intent:nil,age:attack ?? 0),s=spec.scale
        let index=death.map(MonsterVisualSpec.deathFrame) ?? spec.frame(time:time,attackAge:attack,castAge:cast,hurtAge:hurt),next="\(species)-\(death != nil)-\(index)"
        if key != next{monster.image=MeadowMonsterFrames.image(species,index:index,death:death != nil);if death==nil{grounding.update(image:monster.image,soleY:240,contacts:MeadowMonsterFrames.feet(species).map{.init(point:$0,radius:12)})};key=next}
        let base=CGRect(x:650+shift.x-178.5*s,y:395+shift.y-240*s,width:384*s,height:256*s)
        monster.frame=death == nil ? base:CGRect(x:650-178.5*s,y:395-272*s,width:512*s,height:320*s)
        monster.isHidden=death.map{$0>=MonsterVisualSpec.deathDuration} ?? false;monster.layer.zPosition=395
        grounding.spriteFrame=base;grounding.alpha=death.map{CGFloat(1-PartyVisual.smooth($0/0.75))} ?? 1
        hero.setPose(clip:"idle",progress:CGFloat(time.truncatingRemainder(dividingBy:2.4)/2.4));hero.frame=CGRect(x:165-123*0.83,y:420-214*0.83,width:256*0.83,height:256*0.83);hero.layer.zPosition=420
        if !heroGrounded{heroGrounding.update(image:hero.poseSilhouette,soleY:214,contacts:hero.poseContacts.map{.init(point:$0,radius:12)});heroGrounded=true};heroGrounding.spriteFrame=hero.frame
        if let attack,let arrow=spec.projectile(age:attack,foot:PartyPoint(650,395),target:PartyVisual.hitPoint(target:"p1")){
            let path=UIBezierPath();path.move(to:CGPoint(x:arrow.tail.x,y:arrow.tail.y));path.addLine(to:CGPoint(x:arrow.tip.x,y:arrow.tip.y));missile.path=path.cgPath;missile.strokeColor=(species=="ruinDragon" ? UIColor.systemCyan:MeadowPreviewPalette.gold).cgColor
        }else{missile.path=nil}
        onPhase?(death != nil ? "向右吹散退场":attack != nil ? "出招与回位":hurt != nil ? "受击":cast != nil ? "施法":"待机")
    }
    override func layoutSubviews(){super.layoutSubviews();let scale=min(bounds.width/1000,bounds.height/600);world.center=CGPoint(x:bounds.midX,y:bounds.midY);world.transform=CGAffineTransform(scaleX:scale,y:scale);grounding.frame=world.bounds;heroGrounding.frame=world.bounds}
}

/// Draft only: the persistent engine changes once, after explicit confirmation.
final class MeadowEncounterEditorViewController:UIViewController {
    var onSave:(([String])throws->Void)?
    private var draft:MeadowEncounterEditDraft
    private let nodeTitle:String
    private let scroll=UIScrollView(),stack=UIStackView(),actions=UIStackView()
    private let countButton=MeadowPreviewPalette.button("")
    private let statusLabel=MeadowPreviewPalette.label("",size:16)
    private var rows=[UIStackView](),pickers=[UIButton](),descriptions=[UILabel]()
    init(draft:MeadowEncounterEditDraft,title:String){
        self.draft=draft;nodeTitle=title;super.init(nibName:nil,bundle:nil)
        modalPresentationStyle = .formSheet;preferredContentSize=CGSize(width:640,height:650);isModalInPresentation=true
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func viewDidLoad(){
        super.viewDidLoad();view.backgroundColor=MeadowPreviewPalette.panel
        view.addSubview(scroll);view.addSubview(actions);scroll.addSubview(stack)
        for v in [scroll,stack,actions]{v.translatesAutoresizingMaskIntoConstraints=false}
        stack.axis = .vertical;stack.spacing=14;actions.axis = .horizontal;actions.spacing=12;actions.distribution = .fillEqually
        let cancel=MeadowPreviewPalette.button("取消"),save=MeadowPreviewPalette.button("保存遭遇")
        cancel.addAction(UIAction{[weak self] _ in self?.dismiss(animated:true)},for:.touchUpInside)
        save.addAction(UIAction{[weak self] _ in self?.confirmSave()},for:.touchUpInside)
        actions.addArrangedSubview(cancel);actions.addArrangedSubview(save)
        let title=MeadowPreviewPalette.label("编辑遭遇 · "+nodeTitle,size:23,weight:.bold);title.numberOfLines=0
        let note=MeadowPreviewPalette.label("选择每个位置的怪物，可混合编队。保存会恢复此地敌人的生命，已清理地点也会重新开放战斗。",size:17);note.numberOfLines=0;note.textColor=MeadowPreviewPalette.gold
        stack.addArrangedSubview(title);stack.addArrangedSubview(note)
        stack.addArrangedSubview(MeadowPreviewPalette.label("敌人数量",size:18,weight:.bold));stack.addArrangedSubview(countButton)
        countButton.showsMenuAsPrimaryAction=true;countButton.heightAnchor.constraint(equalToConstant:44).isActive=true
        for index in 0..<3 {
            let row=UIStackView();row.axis = .vertical;row.spacing=8;row.isLayoutMarginsRelativeArrangement=true;row.layoutMargins=UIEdgeInsets(top:12,left:12,bottom:12,right:12);row.backgroundColor=UIColor.white.withAlphaComponent(0.08);row.layer.cornerRadius=14;row.layer.cornerCurve = .continuous;row.layer.borderWidth=1;row.layer.borderColor=UIColor.white.withAlphaComponent(0.14).cgColor
            let name=MeadowPreviewPalette.label("怪物 \(index+1)",size:18,weight:.bold),button=MeadowPreviewPalette.button(""),detail=MeadowPreviewPalette.label("",size:16)
            button.showsMenuAsPrimaryAction=true;button.heightAnchor.constraint(equalToConstant:44).isActive=true;detail.numberOfLines=0
            row.addArrangedSubview(name);row.addArrangedSubview(button);row.addArrangedSubview(detail)
            rows.append(row);pickers.append(button);descriptions.append(detail);stack.addArrangedSubview(row)
        }
        statusLabel.numberOfLines=0;statusLabel.textColor = .systemRed;stack.addArrangedSubview(statusLabel)
        let safe=view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            actions.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:16),actions.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-16),actions.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-16),actions.heightAnchor.constraint(equalToConstant:46),
            scroll.topAnchor.constraint(equalTo:safe.topAnchor),scroll.leadingAnchor.constraint(equalTo:safe.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:safe.trailingAnchor),scroll.bottomAnchor.constraint(equalTo:actions.topAnchor,constant:-12),
            stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:16),stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor,constant:-16),stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-16),stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor,constant:-32)])
        refresh()
    }
    private func change(_ edit:(inout MeadowEncounterEditDraft)throws->Void){
        do{try edit(&draft);statusLabel.text=nil;refresh()}catch{statusLabel.text=error.localizedDescription}
    }
    private func refresh(){
        countButton.configuration?.title="\(draft.count) 只"
        countButton.menu=UIMenu(children:(1...draft.maximumCount).map{n in UIAction(title:"\(n)只",state:n==draft.count ? .on:.off){[weak self] _ in self?.change{try $0.setCount(n)}}})
        for row in rows{stack.removeArrangedSubview(row);row.removeFromSuperview()}
        for i in 0..<3 {
            if i<draft.count{stack.insertArrangedSubview(rows[i],at:4+i)}
            guard i<draft.count,let monster=draft.choices.first(where:{$0.id==draft.templates[i]}) else{continue}
            pickers[i].configuration?.title=monster.name
            pickers[i].menu=UIMenu(children:draft.choices.map{choice in UIAction(title:choice.name,state:choice.id==monster.id ? .on:.off){[weak self] _ in self?.change{try $0.setTemplate(choice.id,at:i)}}})
            let a=monster.attack.dice
            descriptions[i].text="生命 \(monster.attributes.maximumHealth) · 行动 \(monster.attributes.baseAP)\n普攻 \(a.count)D\(a.sides) · 射程 \(monster.attack.range)"
        }
    }
    private func confirmSave(){
        let names=draft.templates.compactMap{id in draft.choices.first{$0.id==id}?.name}.joined(separator:" + ")
        let alert=UIAlertController(title:"确认保存并重置？",message:names+"\n此地点的敌人将恢复生命。",preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"取消",style:.cancel))
        alert.addAction(UIAlertAction(title:"保存",style:.destructive){[weak self] _ in
            guard let self,let onSave=self.onSave else{return}
            do{try onSave(self.draft.templates);self.dismiss(animated:true)}catch{self.statusLabel.text="未保存，原配置保留："+error.localizedDescription}
        })
        present(alert,animated:true)
    }
}
