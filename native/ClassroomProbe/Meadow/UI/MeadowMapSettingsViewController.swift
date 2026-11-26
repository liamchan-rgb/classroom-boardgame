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

    private var selectedClasses:[String]=["spellblade","ranger","adventurer","guardian","elementalist","acolyte"]
    private let classButtons=(0..<6).map{_ in UIButton(type:.system)}
    private let classSummaries=(0..<6).map{_ in UILabel()}
    private let studentCount=UIStepper()
    /// Team camps on the map: each team starts at its own camp; teams that meet can fight a PvP duel once.
    private let teamCount=UISegmentedControl(items:["1队","2队","3队"])
    private let teamPickers=(0..<6).map{_ in UISegmentedControl(items:["红队","蓝队","绿队"])}
    private let studentCountLabel=UILabel()
    private var classRows:[UIStackView]=[]
    private var studentNames:[UITextField]=[]
    private var profileLooks:[String:PlayerAppearance]=[:]
    private var profileButtons:[UIButton]=[]
    private var diceButtons:[UIButton]=[]
    /// 班级: a saved roster fills the student rows in one pick.
    private let rosterButton=UIButton(type:.system)
    private var rosterName:String?
    static let rosterStore=ClassRosterStore(url:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ClassroomMeadow/classes-v1.json"))
    private var result: GeneratedMeadowMap?
    private var revision = 0
    private let gold = MeadowPreviewPalette.gold

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    /// Map size presets (number of places); a hand-edited count shows as 自定义.
    private let sizes=[8,10,14,20]
    private let sizePicker=UISegmentedControl(items:["小 · 8","标准 · 10","大 · 14","超大 · 20","自定义"])
    private let advanced=UIStackView()
    private let advancedToggle=UIButton(type:.system)
    private let encounterToggle=UIButton(type:.system)
    private var autoGenerate:DispatchWorkItem?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red:0.80,green:0.88,blue:0.88,alpha:1);MeadowGlassBackdrop.install(in:view)
        // Header: title, the less used things in one menu, close.
        let title=UILabel();title.attributedText=MeadowGlassText.iconLine("map.fill","新地图",size:26,tint:MeadowPreviewPalette.primary,weight:.heavy)
        let subtitle=label("左边定地图，右边排学生，点“开始新行程”。",15,.medium,MeadowPreviewPalette.muted)
        let more=UIButton(type:.system);var moreConfig=UIButton.Configuration.plain();moreConfig.image=UIImage(systemName:"ellipsis.circle");moreConfig.title="更多";moreConfig.imagePadding=6
        more.configuration=moreConfig;more.showsMenuAsPrimaryAction=true
        more.menu=UIMenu(children:[UIDeferredMenuElement.uncached{[weak self] done in
            guard let self else{done([]);return}
            var items:[UIMenuElement]=[
                UIAction(title:"继续已保存行程",image:UIImage(systemName:"arrow.clockwise.circle")){[weak self] _ in self?.continueCampaign()},
                UIAction(title:"历史结算",image:UIImage(systemName:"flag.checkered")){[weak self] _ in self?.showCompletedCampaigns()},
                UIAction(title:"职业说明",image:UIImage(systemName:"info.circle")){[weak self] _ in self?.showClassGuide()},
                UIAction(title:"怪物动作检视",image:UIImage(systemName:"eye")){[weak self] _ in self?.showMonsterGallery()}]
            if self.classroomCampaignReady == nil {items.append(UIAction(title:"进入林地预览",image:UIImage(systemName:"tree"),attributes:self.result==nil ? .disabled:[]){[weak self] _ in self?.enter()})}
            done(items)
        }])
        let closeButton=UIButton(type:.system);closeButton.setImage(UIImage(systemName:"xmark.circle.fill",withConfiguration:UIImage.SymbolConfiguration(pointSize:26)),for:.normal)
        closeButton.tintColor=MeadowPreviewPalette.muted;closeButton.accessibilityLabel="关闭";closeButton.addTarget(self,action:#selector(close),for:.touchUpInside)
        let titles=UIStackView(arrangedSubviews:[title,subtitle]);titles.axis = .vertical;titles.spacing=2
        let header=UIStackView(arrangedSubviews:[titles,UIView(),more,closeButton]);header.alignment = .center;header.spacing=12

        // ── 地图 ──
        let mapCard=card()
        mapCard.addArrangedSubview(section("地图","map"))
        styleSegments(sizePicker);sizePicker.selectedSegmentIndex=1
        sizePicker.addAction(UIAction{[weak self] _ in self?.sizeChosen()},for:.valueChanged)
        mapCard.addArrangedSubview(row("大小",sizePicker))
        styleSegments(teamCount);teamCount.selectedSegmentIndex=0
        teamCount.addAction(UIAction{[weak self] _ in self?.teamCountChanged()},for:.valueChanged)
        mapCard.addArrangedSubview(row("队伍",teamCount))
        mapCard.addArrangedSubview(label("每队一个出生营地；两队相遇可以 PVP 一次。",13,.medium,MeadowPreviewPalette.muted))
        preview.heightAnchor.constraint(equalToConstant:250).isActive=true
        mapCard.addArrangedSubview(preview)
        status.textColor=MeadowPreviewPalette.ink;status.numberOfLines=0;status.font = .systemFont(ofSize:15,weight:.semibold)
        var shuffle=UIButton.Configuration.filled();shuffle.title="换一张";shuffle.image=UIImage(systemName:"dice.fill");shuffle.imagePadding=8
        shuffle.baseBackgroundColor=MeadowPreviewPalette.primary;shuffle.cornerStyle = .large
        let shuffleButton=UIButton(configuration:shuffle);shuffleButton.addTarget(self,action:#selector(newSeed),for:.touchUpInside)
        shuffleButton.setContentHuggingPriority(.required,for:.horizontal)
        let statusRow=UIStackView(arrangedSubviews:[status,shuffleButton]);statusRow.alignment = .center;statusRow.spacing=12
        mapCard.addArrangedSubview(statusRow)
        // Details behind two toggles: the exact counts and seed, and the planned fights and supplies.
        disclosure(advancedToggle,"详细设置（地点数量、道路、种子）"){[weak self] in self?.advanced.isHidden.toggle();self?.refreshToggles()}
        mapCard.addArrangedSubview(advancedToggle)
        advanced.axis = .vertical;advanced.spacing=6;advanced.isHidden=true
        let defaults=["10","4","1","3","1","1",String(UInt64.random(in:0...UInt64.max))]
        for (index,name) in fields.enumerated() {
            let field=UITextField();field.text=defaults[index];field.tag=index
            field.font = .monospacedDigitSystemFont(ofSize:17,weight:.semibold);field.textColor=MeadowPreviewPalette.ink
            field.backgroundColor=MeadowPreviewPalette.glass(.medium);field.borderStyle = .roundedRect
            field.keyboardType = .numberPad;field.accessibilityLabel=name
            field.addTarget(self,action:#selector(inputChanged(_:)),for:.editingChanged)
            inputs.append(field)
            if index<6 {
                field.widthAnchor.constraint(equalToConstant:64).isActive=true
                let slider=UISlider();slider.tag=index;slider.minimumValue=index==0 ? 4:0
                slider.maximumValue=index==0 ? 30:index==5 ? Float(MeadowMapGenerator.maximumExtraRoads(total:10)):9
                slider.value=Float(defaults[index]) ?? 0;slider.minimumTrackTintColor=MeadowPreviewPalette.primary;slider.isContinuous=true
                slider.accessibilityLabel=name+"滑块"
                slider.addTarget(self,action:#selector(slid(_:)),for:.valueChanged)
                sliders.append(slider)
                let pair=UIStackView(arrangedSubviews:[field,slider]);pair.spacing=10;pair.alignment = .center
                advanced.addArrangedSubview(row(name,pair,width:72))
            } else {advanced.addArrangedSubview(row("种子",field,width:72))}
        }
        let suggest=UIButton(type:.system);suggest.setTitle("按总数自动分配",for:.normal);suggest.addTarget(self,action:#selector(suggested),for:.touchUpInside)
        suggest.contentHorizontalAlignment = .leading;advanced.addArrangedSubview(suggest)
        mapCard.addArrangedSubview(advanced)
        disclosure(encounterToggle,"本图的战斗与补给"){[weak self] in self?.encounters.isHidden.toggle();self?.refreshToggles()}
        mapCard.addArrangedSubview(encounterToggle)
        encounters.textColor = MeadowPreviewPalette.ink;encounters.numberOfLines=0;encounters.font = .systemFont(ofSize:14,weight:.medium);encounters.isHidden=true
        mapCard.addArrangedSubview(encounters)
        refreshToggles()

        // ── 学生 ──
        let partyCard=card()
        partyCard.addArrangedSubview(section("学生","person.3.fill"))
        var rosterConfig=UIButton.Configuration.tinted();rosterConfig.image=UIImage(systemName:"person.3.sequence.fill");rosterConfig.imagePadding=8
        rosterConfig.baseForegroundColor=MeadowPreviewPalette.primary;rosterButton.configuration=rosterConfig
        rosterButton.showsMenuAsPrimaryAction=true;rosterButton.accessibilityLabel="班级"
        rosterButton.menu=UIMenu(children:[UIDeferredMenuElement.uncached{[weak self] done in done(self?.rosterMenuItems() ?? [])}])
        refreshRosterButton()
        studentCount.minimumValue=1;studentCount.maximumValue=6;studentCount.value=2
        studentCount.addTarget(self,action:#selector(refreshPartySummary),for:.valueChanged)
        studentCountLabel.textColor=MeadowPreviewPalette.ink;studentCountLabel.font = .boldSystemFont(ofSize:16)
        let countRow=UIStackView(arrangedSubviews:[rosterButton,UIView(),studentCountLabel,studentCount]);countRow.alignment = .center;countRow.spacing=10
        partyCard.addArrangedSubview(countRow)
        for (i,button) in classButtons.enumerated() {
            let number=label("\(i+1)",16,.heavy,.white);number.textAlignment = .center;number.backgroundColor=MeadowPreviewPalette.primary
            number.layer.cornerRadius=13;number.clipsToBounds=true
            number.widthAnchor.constraint(equalToConstant:26).isActive=true;number.heightAnchor.constraint(equalToConstant:26).isActive=true
            var cfg=UIButton.Configuration.tinted();cfg.baseForegroundColor=MeadowPreviewPalette.ink;cfg.baseBackgroundColor=MeadowPreviewPalette.primary.withAlphaComponent(0.16)
            cfg.cornerStyle = .medium;cfg.imagePadding=6;cfg.indicator = .popup
            cfg.contentInsets=NSDirectionalEdgeInsets(top:6,leading:10,bottom:6,trailing:10)
            button.configuration=cfg;button.showsMenuAsPrimaryAction=true;button.accessibilityLabel="P\(i+1)职业"
            button.setContentHuggingPriority(.defaultLow,for:.horizontal)
            button.menu=UIMenu(children:[UIDeferredMenuElement.uncached{[weak self] done in done(self?.classMenuItems(for:i) ?? [])}])
            let summary=classSummaries[i];summary.numberOfLines=0
            let name=UITextField();name.placeholder="姓名";name.borderStyle = .roundedRect;name.textColor = MeadowPreviewPalette.ink;name.backgroundColor=MeadowPreviewPalette.glass(.medium);studentNames.append(name)
            name.widthAnchor.constraint(equalToConstant:110).isActive=true
            let profiles=UIButton(type:.system);profileButtons.append(profiles)
            // One look button: shows the chosen face; its menu picks a random look or a saved character.
            let dice=UIButton(type:.system);dice.setTitle("外观",for:.normal);dice.setImage(UIImage(systemName:"dice.fill"),for:.normal)
            dice.accessibilityLabel="P\(i+1)外观";dice.showsMenuAsPrimaryAction=true
            dice.menu=UIMenu(children:[UIDeferredMenuElement.uncached{[weak self] done in
                guard let self else{done([]);return}
                var items:[UIMenuElement]=[UIAction(title:"随机外观",image:UIImage(systemName:"dice")){[weak self] _ in
                    guard let self else{return}
                    let key="p\(i+1)",others=self.profileLooks.filter{$0.key != key}.map(\.value)
                    self.profileLooks[key]=PlayerAppearance.random(excluding:others+(self.profileLooks[key].map{[$0]} ?? []))
                    self.showFace(i)
                }]
                // Only the used character slots (of 50).
                let saved:[UIMenuElement]=(1...MeadowSlotStore.profileCount).compactMap{slot in
                    guard let found=try? MeadowTeacherCoordinator.slotStore.profile(slot) else{return nil}
                    let entry:MeadowSaveSlot<MeadowPlayerProfile>=found
                    return UIAction(title:entry.value.name,subtitle:"人物槽 \(slot)"){[weak self] _ in
                        guard let self else{return};name.text=entry.value.name;self.profileLooks["p\(i+1)"]=entry.value.appearance;self.showFace(i)
                    }
                }
                if !saved.isEmpty {items.append(UIMenu(title:"读取人物档案",image:UIImage(systemName:"person.crop.square"),children:saved))}
                done(items)
            }])
            diceButtons.append(dice)
            dice.setContentCompressionResistancePriority(.required,for:.horizontal);dice.widthAnchor.constraint(greaterThanOrEqualToConstant:86).isActive=true
            let team=teamPickers[i];team.selectedSegmentIndex=0;styleSegments(team,size:13);team.accessibilityLabel="P\(i+1)队伍"
            team.widthAnchor.constraint(equalToConstant:150).isActive=true
            let line=UIStackView(arrangedSubviews:[number,name,dice,button,team]);line.spacing=8;line.alignment = .center
            line.heightAnchor.constraint(greaterThanOrEqualToConstant:40).isActive=true
            classRows.append(line);partyCard.addArrangedSubview(line)
        }
        refreshPartySummary()
        // The question bank lives in the top bar ("题库"); a new trip starts with it (roadside finds become quizzes).
        quizLabel.font = .systemFont(ofSize:14,weight:.semibold);quizLabel.numberOfLines=2
        partyCard.addArrangedSubview(quizLabel);refreshQuizLabel()

        var startConfig=UIButton.Configuration.filled();startConfig.title="开始新行程";startConfig.image=UIImage(systemName:"play.fill");startConfig.imagePadding=10
        startConfig.baseBackgroundColor=MeadowPreviewPalette.primary;startConfig.cornerStyle = .large
        startConfig.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer{v in var v=v;v.font=UIFont.boldSystemFont(ofSize:19);return v}
        startCampaignButton.configuration=startConfig
        startCampaignButton.addTarget(self,action:#selector(startCampaign),for:.touchUpInside)
        startCampaignButton.heightAnchor.constraint(equalToConstant:52).isActive=true

        // Both cards reach down to the start button's bottom edge (a flexible spacer takes the slack).
        for c in [mapCard,partyCard] {let gap=UIView();gap.setContentHuggingPriority(UILayoutPriority(1),for:.vertical);gap.setContentCompressionResistancePriority(UILayoutPriority(1),for:.vertical);c.addArrangedSubview(gap)}
        let leftScroll=UIScrollView(),rightScroll=UIScrollView()
        leftScroll.addSubview(mapCard);rightScroll.addSubview(partyCard)
        for v in [header,leftScroll,rightScroll,mapCard,partyCard,startCampaignButton] {v.translatesAutoresizingMaskIntoConstraints=false}
        view.addSubview(header);view.addSubview(leftScroll);view.addSubview(rightScroll);view.addSubview(startCampaignButton)
        let guide=view.safeAreaLayoutGuide
        func fill(_ c:UIStackView,_ s:UIScrollView)->[NSLayoutConstraint] {
            [c.leadingAnchor.constraint(equalTo:s.contentLayoutGuide.leadingAnchor),c.trailingAnchor.constraint(equalTo:s.contentLayoutGuide.trailingAnchor),
             c.topAnchor.constraint(equalTo:s.contentLayoutGuide.topAnchor),c.bottomAnchor.constraint(equalTo:s.contentLayoutGuide.bottomAnchor),
             c.widthAnchor.constraint(equalTo:s.frameLayoutGuide.widthAnchor),
             c.heightAnchor.constraint(greaterThanOrEqualTo:s.frameLayoutGuide.heightAnchor)]
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo:guide.leadingAnchor,constant:22),header.trailingAnchor.constraint(equalTo:guide.trailingAnchor,constant:-22),
            header.topAnchor.constraint(equalTo:guide.topAnchor,constant:14),
            leftScroll.leadingAnchor.constraint(equalTo:guide.leadingAnchor,constant:18),leftScroll.topAnchor.constraint(equalTo:header.bottomAnchor,constant:12),
            leftScroll.bottomAnchor.constraint(equalTo:guide.bottomAnchor,constant:-14),leftScroll.widthAnchor.constraint(equalTo:guide.widthAnchor,multiplier:0.44),
            rightScroll.leadingAnchor.constraint(equalTo:leftScroll.trailingAnchor,constant:16),rightScroll.trailingAnchor.constraint(equalTo:guide.trailingAnchor,constant:-18),
            rightScroll.topAnchor.constraint(equalTo:header.bottomAnchor,constant:12),rightScroll.bottomAnchor.constraint(equalTo:startCampaignButton.topAnchor,constant:-12),
            startCampaignButton.leadingAnchor.constraint(equalTo:rightScroll.leadingAnchor),startCampaignButton.trailingAnchor.constraint(equalTo:rightScroll.trailingAnchor),
            startCampaignButton.bottomAnchor.constraint(equalTo:guide.bottomAnchor,constant:-14),
        ]+fill(mapCard,leftScroll)+fill(partyCard,rightScroll))
        changed()
    }
    // MARK: layout helpers
    private func card()->UIStackView {
        let c=UIStackView();c.axis = .vertical;c.spacing=10;c.isLayoutMarginsRelativeArrangement=true
        c.directionalLayoutMargins=NSDirectionalEdgeInsets(top:16,leading:16,bottom:16,trailing:16)
        c.backgroundColor=MeadowPreviewPalette.glass(.thick);c.layer.cornerRadius=18;c.layer.cornerCurve = .continuous
        c.layer.borderColor=UIColor.white.withAlphaComponent(0.7).cgColor;c.layer.borderWidth=1
        return c
    }
    private func section(_ text:String,_ icon:String)->UILabel {
        let l=UILabel();l.attributedText=MeadowGlassText.iconLine(icon,text,size:19,tint:MeadowPreviewPalette.primary,weight:.bold);return l
    }
    private func label(_ text:String,_ size:CGFloat,_ weight:UIFont.Weight,_ color:UIColor)->UILabel {
        let l=UILabel();l.text=text;l.font = .systemFont(ofSize:size,weight:weight);l.textColor=color;l.numberOfLines=0;return l
    }
    private func row(_ title:String,_ control:UIView,width:CGFloat=44)->UIStackView {
        let l=label(title,15,.bold,MeadowPreviewPalette.ink);l.widthAnchor.constraint(equalToConstant:width).isActive=true
        let r=UIStackView(arrangedSubviews:[l,control]);r.spacing=10;r.alignment = .center;return r
    }
    private func styleSegments(_ s:UISegmentedControl,size:CGFloat=15) {
        s.selectedSegmentTintColor=MeadowPreviewPalette.primary
        s.setTitleTextAttributes([.foregroundColor:MeadowPreviewPalette.ink,.font:UIFont.boldSystemFont(ofSize:size)],for:.normal)
        s.setTitleTextAttributes([.foregroundColor:UIColor.white,.font:UIFont.boldSystemFont(ofSize:size)],for:.selected)
    }
    private var toggleTitles:[UIButton:String]=[:]
    private func disclosure(_ b:UIButton,_ title:String,_ action:@escaping ()->Void) {
        toggleTitles[b]=title;b.contentHorizontalAlignment = .leading
        b.addAction(UIAction{_ in action()},for:.touchUpInside)
    }
    private func refreshToggles() {
        for (b,title) in toggleTitles {
            let open=b===advancedToggle ? !advanced.isHidden:!encounters.isHidden
            var c=UIButton.Configuration.plain();c.title=title;c.image=UIImage(systemName:open ? "chevron.down":"chevron.right");c.imagePadding=6
            c.baseForegroundColor=MeadowPreviewPalette.primary;c.contentInsets = .zero;b.configuration=c
        }
    }
    private func sizeChosen() {
        guard sizes.indices.contains(sizePicker.selectedSegmentIndex) else{advanced.isHidden=false;refreshToggles();return}
        inputs[0].text=String(sizes[sizePicker.selectedSegmentIndex]);suggested()
    }
    private static func classBadge(_ id:String,side:CGFloat=22)->UIImage? {
        let cap=id.prefix(1).uppercased()+id.dropFirst()
        guard let image=UIImage(named:"ClassBadge"+cap) else{return nil}
        let size=CGSize(width:side,height:side)
        return UIGraphicsImageRenderer(size:size).image{r in
            r.cgContext.interpolationQuality = .none
            image.draw(in:CGRect(origin:.zero,size:size))
        }.withRenderingMode(.alwaysOriginal)
    }
    private func classMenuItems(for row:Int)->[UIMenuElement] {
        let catalog=try? MeadowCampaignSession.catalog()
        let current=selectedClasses[row]
        return MeadowPartyConfiguration.classTiers.map{tier in
            UIMenu(title:tier.title,children:tier.ids.map{id in
                let def=try? catalog?.playerClass(id)
                let name=def?.name ?? id
                let skills=(def?.skills ?? []).compactMap{try? catalog?.skill($0).name}.joined(separator:" / ")
                let sub=def.map{"HP \($0.attributes.maximumHealth) · AP \($0.attributes.baseAP)/\($0.attributes.maximumAP) · \(skills)"} ?? ""
                return UIAction(title:name,subtitle:sub,image:Self.classBadge(id,side:24),state:current==id ? .on:.off){[weak self] _ in
                    guard let self else{return}
                    self.selectedClasses[row]=id
                    self.refreshPartySummary()
                }
            })
        }
    }
    private func showClassGuide() {
        present(MeadowClassGuideController(),animated:true)
    }
    private let quizLabel=UILabel()
    /// The app's question bank (top bar "题库"), given to the new trip.
    private var quizBank:[QuizQuestion]? {let q=QuizLibrary.shared.activeQuestions;return q.isEmpty ? nil:q}
    private func refreshQuizLabel(){
        if let bank=quizBank {quizLabel.text="题库：\(QuizLibrary.shared.active ?? "")（\(bank.count) 题，顶栏课程菜单可切换）";quizLabel.textColor=MeadowPreviewPalette.primary}
        else {quizLabel.text="题库：未选课程（顶栏课程菜单导入；不选则地图上是普通随机事件）";quizLabel.textColor=MeadowPreviewPalette.muted}
    }
    private func button(_ title:String,action:Selector) -> UIButton {
        let b=UIButton(type:.system);var c=UIButton.Configuration.filled();c.title=title
        c.baseBackgroundColor=MeadowPreviewPalette.primary;c.baseForegroundColor = .white
        c.contentInsets=NSDirectionalEdgeInsets(top:9,leading:10,bottom:9,trailing:10);b.configuration=c
        b.addTarget(self,action:action,for:.touchUpInside);return b
    }
    private func configuration() throws -> MeadowMapConfiguration {
        guard let total=Int(inputs[0].text ?? ""),let combat=Int(inputs[1].text ?? ""),let boss=Int(inputs[2].text ?? ""),
              let reward=Int(inputs[3].text ?? ""),let empty=Int(inputs[4].text ?? ""),let roads=Int(inputs[5].text ?? ""),
              let seed=UInt64(inputs[6].text ?? "") else { throw NSError(domain:"地图",code:1,userInfo:[NSLocalizedDescriptionKey:"请输入完整的非负整数。总数范围4—30。种子为0—18446744073709551615。"]) }
        var c=MeadowMapConfiguration();c.total=total;c.combat=combat;c.boss=boss;c.reward=reward;c.empty=empty;c.extraRoads=roads;c.seed=seed
        c.starts=teamCount.selectedSegmentIndex>0 ? teamCount.selectedSegmentIndex+1:nil
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
            status.text="正在生成…"
            generateButton.isEnabled=true
            sizePicker.selectedSegmentIndex=sizes.firstIndex(of:c.total).flatMap{i in (try? MeadowMapConfiguration.suggested(total:c.total).changingTotal(to:c.total)).map{s in s.combat==c.combat && s.boss==c.boss && s.reward==c.reward && s.empty==c.empty ? i:4}} ?? 4
            // The preview follows every change by itself (a moment after the last one).
            autoGenerate?.cancel()
            let work=DispatchWorkItem{[weak self] in self?.generate()}
            autoGenerate=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.35,execute:work)
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
                    let camps=map.map.nodes.filter{$0.kind == .start}.count
                    self.status.text="\(map.map.nodes.count) 个地点：战斗 \(config.combat) · 首领 \(config.boss) · 补给 \(config.reward) · 空地 \(config.empty)"+(camps>1 ? " · \(camps) 个营地":"")
                case .failure(let error): self.status.text=error.localizedDescription
                }
            }
        }
    }
    // MARK: 班级

    /// The camps are part of the map: a new team count needs a new road preview.
    private func teamCountChanged() {
        refreshPartySummary()
        changed()
    }
    /// Row i's look shown as a round face on its dice button (the portrait bakes in the background on first use).
    private func showFace(_ i:Int) {
        guard diceButtons.indices.contains(i) else{return}
        let dice=diceButtons[i],key="p\(i+1)"
        guard let look=profileLooks[key] else{
            dice.setTitle("外观",for:.normal);dice.setImage(UIImage(systemName:"dice.fill"),for:.normal);return
        }
        dice.setTitle(" 外观",for:.normal)
        let pixel=PixelHeroLook(body:look.body,armor:look.armor(worn:nil),hair:look.hair,hairColor:look.hairColor,face:look.face)
        func show(_ image:UIImage){
            guard self.profileLooks[key]==look else{return}
            let size=CGSize(width:30,height:30)
            let face=UIGraphicsImageRenderer(size:size).image{_ in UIBezierPath(ovalIn:CGRect(origin:.zero,size:size)).addClip();image.draw(in:CGRect(origin:.zero,size:size))}
            dice.setImage(face.withRenderingMode(.alwaysOriginal),for:.normal)
        }
        if let ready=PixelHeroAtlas.portrait(pixel,ready:{if let image=PixelHeroAtlas.portrait(pixel){show(image)}}) {show(ready)}
    }
    private func refreshRosterButton() {
        rosterButton.configuration?.title=rosterName.map{"班级：\($0)"} ?? "选择班级 / 创建班级"
    }
    private func rosterMenuItems()->[UIMenuElement] {
        let saved=(try? Self.rosterStore.all()) ?? []
        var items:[UIMenuElement]=saved.map{roster in
            UIAction(title:roster.name,subtitle:"\(roster.students.count)人 · "+roster.students.map{$0.name.isEmpty ? "未命名":$0.name}.joined(separator:"、"),
                     image:UIImage(systemName:"person.3.fill"),state:roster.name==rosterName ? .on:.off){[weak self] _ in self?.apply(roster)}
        }
        let create=UIAction(title:saved.isEmpty ? "用下面的学生创建班级…":"把下面的学生存为班级…",image:UIImage(systemName:"plus.circle")){[weak self] _ in self?.askToSaveRoster()}
        items.append(UIMenu(options:.displayInline,children:[create]))
        if !saved.isEmpty {
            items.append(UIMenu(title:"删除班级",image:UIImage(systemName:"trash"),options:.destructive,children:saved.map{roster in
                UIAction(title:roster.name,attributes:.destructive){[weak self] _ in self?.confirmDelete(roster.name)}
            }))
        }
        return items
    }
    /// Fill the rows from a class: count, names, looks, jobs and teams (a different team count invalidates the road preview).
    private func apply(_ roster:ClassRoster) {
        let count=min(ClassRoster.maximumStudents,roster.students.count)
        studentCount.value=Double(count)
        if teamCount.selectedSegmentIndex != roster.teamCount-1 {teamCount.selectedSegmentIndex=roster.teamCount-1;teamCountChanged()}
        let ids=MeadowPartyConfiguration.classIDs
        for (i,student) in roster.students.prefix(count).enumerated() {
            studentNames[i].text=student.name
            profileLooks["p\(i+1)"]=student.appearance
            selectedClasses[i]=ids.contains(student.classID) ? student.classID:"ranger"
            teamPickers[i].selectedSegmentIndex=student.team;teamPickers[i].tag=1
            profileButtons[i].setTitle("读取人物档案",for:.normal)
            showFace(i)
        }
        rosterName=roster.name;refreshRosterButton();refreshPartySummary()
        if result != nil {status.text="已载入班级“\(roster.name)”（\(count) 人）"}
    }
    private func currentRoster(named name:String)->ClassRoster {
        let teams=teamCount.selectedSegmentIndex+1
        return ClassRoster(name:name,students:(0..<Int(studentCount.value)).map{i in
            ClassRoster.Student(name:studentNames[i].text ?? "",appearance:profileLooks["p\(i+1)"],
                                classID:selectedClasses[i],team:teams<2 ? 0:max(0,teamPickers[i].selectedSegmentIndex))
        })
    }
    private func askToSaveRoster() {
        view.endEditing(true)
        let alert=UIAlertController(title:"保存为班级",message:"保存下面\(Int(studentCount.value))名学生的姓名、外观、职业和队伍。以后新地图选这个班级即可一键排好。同名班级会被替换。",preferredStyle:.alert)
        alert.addTextField{[rosterName] field in field.placeholder="班级名称，例如：三年级二班";field.text=rosterName}
        alert.addAction(UIAlertAction(title:"取消",style:.cancel))
        alert.addAction(UIAlertAction(title:"保存",style:.default){[weak self,weak alert] _ in
            guard let self else{return}
            do{
                let saved=try Self.rosterStore.save(self.currentRoster(named:alert?.textFields?.first?.text ?? ""))
                self.rosterName=saved.name;self.refreshRosterButton()
                self.status.text="已保存班级“\(saved.name)”（\(saved.students.count)人）。"
            }catch{self.status.text="班级未保存："+error.localizedDescription}
        })
        present(alert,animated:true)
    }
    private func confirmDelete(_ name:String) {
        let alert=UIAlertController(title:"删除班级“\(name)”？",message:"只删除这个班级名单，不影响任何行程和人物档案。",preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"取消",style:.cancel))
        alert.addAction(UIAlertAction(title:"删除",style:.destructive){[weak self] _ in
            guard let self else{return}
            do{try Self.rosterStore.delete(name);if self.rosterName==name{self.rosterName=nil;self.refreshRosterButton()};self.status.text="已删除班级“\(name)”。"}
            catch{self.status.text="删除失败："+error.localizedDescription}
        })
        present(alert,animated:true)
    }

    static func campaignStore()->MeadowCampaignStore {
        let base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        return MeadowCampaignStore(url:base.appendingPathComponent("ClassroomMeadow/campaign-v1.json"))
    }
    private var partyConfiguration:MeadowPartyConfiguration {
        .init(playerClassID:selectedClasses[0],companionClassID:selectedClasses[1])
    }
    @objc private func refreshPartySummary() {
        do {
            let catalog=try MeadowCampaignSession.catalog()
            studentCountLabel.text="\(Int(studentCount.value)) 人"
            for (i,button) in classButtons.enumerated() {
                classRows[i].isHidden=i>=Int(studentCount.value)
                let id=selectedClasses[i]
                let def=try catalog.playerClass(id)
                button.configuration?.title=def.name
                button.configuration?.image=Self.classBadge(id,side:22)
                classSummaries[i].text=try MeadowPartyConfiguration.summary(for:id,catalog:catalog)
            }
            // Team pickers: only with several teams, and only the teams that exist; new rows default to round-robin.
            let teams=teamCount.selectedSegmentIndex+1
            for (i,picker) in teamPickers.enumerated() {
                picker.isHidden=teams<2
                for s in 0..<3 {picker.setEnabled(s<teams,forSegmentAt:s)}
                if picker.selectedSegmentIndex>=teams || (teams>1 && picker.tag==0) {picker.selectedSegmentIndex=i%teams;picker.tag=1}
                if teams<2 {picker.tag=0}
            }
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
                    try save.validate(appearances:["forester","wayfarer"],equipment:CampInventorySession.allSupportedEquipment)
                    units=save.archive.state.units;appearance=save.appearanceID
                }
                try store.preserveCompletedCampaign()
                let session=try MeadowCampaignSession.new(layout:result,appearanceID:appearance,playerClassID:config.playerClassID,companionClassID:config.companionClassID,studentClasses:Array(self.selectedClasses.prefix(Int(self.studentCount.value))),studentNames:self.studentNames.prefix(Int(self.studentCount.value)).map{$0.text ?? ""},playerAppearances:self.profileLooks,loadouts:units,difficulty:GameDifficulty.lastChosen,quizBank:self.quizBank,studentTeams:self.teamPickers.prefix(Int(self.studentCount.value)).map{max(0,$0.selectedSegmentIndex)},persist:store.write)
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
        UIColor(red:0.86,green:0.92,blue:0.88,alpha:0.9).setFill();UIBezierPath(roundedRect:bounds,cornerRadius:12).fill()
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


/// Scrollable 14-class guide with badges, base stats, and skills.
private final class MeadowClassGuideController:UIViewController {
    private let scroll=UIScrollView(),stack=UIStackView(),closeButton=MeadowPreviewPalette.button("关闭")
    init(){super.init(nibName:nil,bundle:nil);modalPresentationStyle = .formSheet;preferredContentSize=CGSize(width:680,height:640)}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override func viewDidLoad(){
        super.viewDidLoad();view.backgroundColor=MeadowPreviewPalette.panel
        scroll.translatesAutoresizingMaskIntoConstraints=false;stack.translatesAutoresizingMaskIntoConstraints=false;closeButton.translatesAutoresizingMaskIntoConstraints=false
        stack.axis = .vertical;stack.spacing=12
        view.addSubview(scroll);scroll.addSubview(stack);view.addSubview(closeButton)
        closeButton.addAction(UIAction{[weak self] _ in self?.dismiss(animated:true)},for:.touchUpInside)
        let title=MeadowPreviewPalette.label("全部 14 职业图鉴",size:24,weight:.heavy);stack.addArrangedSubview(title)
        if let catalog=try? MeadowCampaignSession.catalog() {
            for tier in MeadowPartyConfiguration.classTiers {
                let header=MeadowPreviewPalette.label(tier.title,size:17,weight:.bold);header.textColor=MeadowPreviewPalette.primary
                stack.addArrangedSubview(header)
                for id in tier.ids {
                    guard let summary=try? MeadowPartyConfiguration.summary(for:id,catalog:catalog) else{continue}
                    let row=UIStackView();row.spacing=12;row.alignment = .center;row.isLayoutMarginsRelativeArrangement=true
                    row.layoutMargins=UIEdgeInsets(top:10,left:12,bottom:10,right:12);row.backgroundColor=MeadowPreviewPalette.glass(.medium)
                    row.layer.cornerRadius=12;row.layer.cornerCurve = .continuous
                    let cap=id.prefix(1).uppercased()+id.dropFirst()
                    let icon=UIImageView(image:UIImage(named:"ClassBadge"+cap));icon.contentMode = .scaleAspectFit;icon.layer.magnificationFilter = .nearest
                    icon.widthAnchor.constraint(equalToConstant:48).isActive=true;icon.heightAnchor.constraint(equalToConstant:48).isActive=true
                    let label=MeadowPreviewPalette.label(summary,size:15,weight:.medium);label.numberOfLines=0
                    row.addArrangedSubview(icon);row.addArrangedSubview(label);stack.addArrangedSubview(row)
                }
            }
        }
        let safe=view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo:safe.leadingAnchor,constant:16),closeButton.trailingAnchor.constraint(equalTo:safe.trailingAnchor,constant:-16),
            closeButton.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-14),closeButton.heightAnchor.constraint(equalToConstant:44),
            scroll.topAnchor.constraint(equalTo:safe.topAnchor),scroll.leadingAnchor.constraint(equalTo:safe.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo:safe.trailingAnchor),scroll.bottomAnchor.constraint(equalTo:closeButton.topAnchor,constant:-10),
            stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-16),
            stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor,constant:-16),
            stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor,constant:-32)
        ])
    }
}

/// A separate art inspection screen, never attached to the saved rule engine.
private final class MeadowMonsterGalleryController:UIViewController {
    private let gallery=MeadowMonsterGalleryView()
    private let prevButton=MeadowPreviewPalette.button("◀ 上一只")
    private let pickerButton=UIButton(type:.system)
    private let nextButton=MeadowPreviewPalette.button("下一只 ▶")
    private let titleLabel=MeadowPreviewPalette.label("怪物动作检视（22 种）",size:26,weight:.heavy)
    private let phase=MeadowPreviewPalette.label("",size:19,weight:.bold)
    private let close=MeadowPreviewPalette.button("返回"),replay=MeadowPreviewPalette.button("重播动作")
    private var selectedIndex=0
    private static let groups:[(title:String,ids:[String])]=[
        ("开局林缘（4）",["slime","hopShroom","acornBandit","bubbleCrab"]),
        ("中段幽林（5）",["wolf","goblinArcher","stingWasp","brambleSprite","goblinShaman"]),
        ("深处遗迹（4）",["stoneGuardian","emberLizard","shadowOwl","runeKnight"]),
        ("禁区精英（2）",["crystalGolem","frostAlphaWolf"]),
        ("首领 Boss（7）",["mushroomKing","caveTroll","goblinWarlord","thornTreant","ruinDragon","frostPhoenix","eclipseBehemoth"])
    ]
    private var currentID:String { MonsterVisualSpec.ids[selectedIndex] }
    init(){super.init(nibName:nil,bundle:nil);modalPresentationStyle = .fullScreen}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override var prefersStatusBarHidden:Bool{true}
    override var supportedInterfaceOrientations:UIInterfaceOrientationMask{.landscape}
    override func viewDidLoad(){
        super.viewDidLoad();view.backgroundColor=MeadowPreviewPalette.panel
        for v in [gallery,prevButton,pickerButton,nextButton,titleLabel,phase,close,replay]{view.addSubview(v)}
        phase.numberOfLines=2;phase.font=MeadowPreviewPalette.font(17)
        var cfg=UIButton.Configuration.filled();cfg.baseBackgroundColor=MeadowPreviewPalette.primary;cfg.baseForegroundColor = .white;cfg.cornerStyle = .medium;cfg.indicator = .popup
        pickerButton.configuration=cfg;pickerButton.showsMenuAsPrimaryAction=true
        pickerButton.menu=UIMenu(children:[UIDeferredMenuElement.uncached{[weak self] done in done(self?.monsterMenuItems() ?? [])}])
        prevButton.addAction(UIAction{[weak self] _ in self?.step(-1)},for:.touchUpInside)
        nextButton.addAction(UIAction{[weak self] _ in self?.step(1)},for:.touchUpInside)
        gallery.onPhase={ [weak self] value in self?.phase.text=value+" · 仅外观检视，不消耗行程资源" }
        close.addAction(UIAction{[weak self] _ in self?.dismiss(animated:true)},for:.touchUpInside)
        replay.addAction(UIAction{[weak self] _ in guard let self else{return};self.gallery.select(self.currentID)},for:.touchUpInside)
        refreshSelection()
    }
    private func step(_ delta:Int) {
        let n=MonsterVisualSpec.ids.count
        selectedIndex=(selectedIndex+delta+n)%n
        refreshSelection()
    }
    private func refreshSelection() {
        let catalog=try? GameCatalog.initial()
        let name=(try? catalog?.monster(currentID).name) ?? currentID
        let spec=MonsterVisualSpec.find(currentID)
        let tag=spec?.ranged == true ? " · 远程":""
        pickerButton.configuration?.title="\(name)（\(selectedIndex+1)/\(MonsterVisualSpec.ids.count)\(tag)）"
        gallery.select(currentID)
    }
    private func monsterMenuItems()->[UIMenuElement] {
        let catalog=try? GameCatalog.initial()
        return Self.groups.map{group in
            UIMenu(title:group.title,children:group.ids.map{id in
                let def=try? catalog?.monster(id)
                let name=def?.name ?? id
                let sub=def.map{"HP \($0.attributes.maximumHealth) · 盾 \($0.shield) · \($0.attack.dice.label)"+($0.attack.range>0 ? " · 远程":"")} ?? ""
                return UIAction(title:name,subtitle:sub,state:id==currentID ? .on:.off){[weak self] _ in
                    guard let self,let idx=MonsterVisualSpec.ids.firstIndex(of:id) else{return}
                    self.selectedIndex=idx;self.refreshSelection()
                }
            })
        }
    }
    override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);gallery.start()}
    override func viewWillDisappear(_ animated:Bool){super.viewWillDisappear(animated);gallery.stop()}
    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews();let safe=view.safeAreaInsets,left=max(16,safe.left+8),right=view.bounds.width-max(16,safe.right+8),width=right-left,top=max(12,safe.top+8),bottom=view.bounds.height-max(12,safe.bottom+8)
        titleLabel.frame=CGRect(x:left,y:top,width:320,height:36);close.frame=CGRect(x:right-90,y:top,width:90,height:38)
        let navW:CGFloat=120
        prevButton.frame=CGRect(x:left,y:top+46,width:navW,height:42)
        nextButton.frame=CGRect(x:right-navW,y:top+46,width:navW,height:42)
        pickerButton.frame=CGRect(x:left+navW+10,y:top+46,width:max(120,width-2*navW-20),height:42)
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
            let row=UIStackView();row.axis = .vertical;row.spacing=8;row.isLayoutMarginsRelativeArrangement=true;row.layoutMargins=UIEdgeInsets(top:12,left:12,bottom:12,right:12);row.backgroundColor=MeadowPreviewPalette.glass(.medium);row.layer.cornerRadius=14;row.layer.cornerCurve = .continuous;row.layer.borderWidth=1;row.layer.borderColor=UIColor.white.withAlphaComponent(0.8).cgColor
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
