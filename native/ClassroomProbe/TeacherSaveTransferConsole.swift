import SwiftUI
import UniformTypeIdentifiers
import MeadowWorldSupport

struct TeacherSaveTransferRequest:Identifiable {
    let id=UUID()
    var importing:Bool=false
    var selection:Set<MeadowSlotAddress>?
}
private struct MeadowSaveDocument:FileDocument {
    static var readableContentTypes:[UTType]{[.json]}
    var data:Data
    init(data:Data){self.data=data}
    init(configuration:ReadConfiguration)throws{guard let bytes=configuration.file.regularFileContents else{throw CocoaError(.fileReadCorruptFile)};data=bytes}
    func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper{FileWrapper(regularFileWithContents:data)}
}
private struct TransferSlotRow:Identifiable {
    let address:MeadowSlotAddress
    let title:String
    let error:String?
    var id:String{address.id}
}
/// Private file picker/exporter. It writes slots, never the live campaign.
struct TeacherSaveTransferConsole:View {
    let directory:URL
    let request:TeacherSaveTransferRequest
    let onClose:()->Void
    @State private var initialized=false
    @State private var importing=false
    @State private var picker=false
    @State private var exporter=false
    @State private var working=false
    @State private var notice="选择需要备份的槽位。文件仅在你选择的保存位置写入。"
    @State private var rows:[TransferSlotRow]=[]
    @State private var selection=Set<MeadowSlotAddress>()
    @State private var package:MeadowSaveTransfer?
    @State private var destinations:[MeadowSlotAddress:Int]=[:]
    @State private var sourceName=""
    @State private var backups:[MeadowImportBackup]=[]
    @State private var document=MeadowSaveDocument(data:Data())
    @State private var filename="Meadow-存档备份"
    @State private var confirm=false
    @State private var confirmation=""
    private var selectedAddresses:[MeadowSlotAddress] {importing ? (package?.addresses.filter{selection.contains($0)} ?? []):rows.filter{$0.error==nil && selection.contains($0.address)}.map(\.address)}
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    Picker("操作",selection:$importing){Text("导出备份").tag(false);Text("导入备份").tag(true)}.pickerStyle(.segmented)
                    Text(notice).font(.callout)
                    if working{ProgressView("正在校验与处理文件…")}
                }.glassRow()
                if importing{importForm}else{exportForm}
            }.glassSheet().disabled(working).navigationTitle("人物与行程 · 导入导出")
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("关闭"){onClose()}.disabled(working)}}
                .interactiveDismissDisabled(working)
                .onAppear{if !initialized{initialized=true;importing=request.importing;refresh(selectDefaults:true)}}
                .onChange(of:importing){_,value in selection=value ? Set(package?.addresses ?? []):Set(rows.filter{$0.error==nil}.map(\.address))}
                .fileImporter(isPresented:$picker,allowedContentTypes:[.json]){result in switch result{case .success(let url):readFile(url);case .failure(let error):notice=isCancellation(error) ? "已取消选取，槽位未改变。":"文件选取失败："+error.localizedDescription}}
                .fileExporter(isPresented:$exporter,document:document,contentType:.json,defaultFilename:filename){result in
                    switch result{case .success:notice="备份文件已保存到你选择的位置。";case .failure(let error):notice=isCancellation(error) ? "已取消导出，槽位未改变。":"导出失败："+error.localizedDescription}
                    document=MeadowSaveDocument(data:Data())
                }
                .alert("确认导入到存档槽",isPresented:$confirm){Button("取消",role:.cancel){};Button("确认导入",role:.destructive){performImport()}}message:{Text(confirmation)}
        }
    }
    private var exportForm:some View {
        Group {
            Section("勾选需要导出的已保存槽位") {
                Text("可选单个或多个，人物与行程可合为一个JSON备份。当前游戏进度请先在上一页保存到行程槽；这里不会自动覆盖槽位。").font(.caption)
                HStack{Button("全选可读槽"){selection=Set(rows.filter{$0.error==nil}.map(\.address))};Button("全部取消"){selection=[]}}.buttonStyle(.bordered)
                ForEach(rows){row in
                    Toggle(isOn:selected(row.address)){
                        Text("\(row.address.kind.title)槽\(row.address.slot) · "+row.title)
                        if let error=row.error{Text("原文件保留："+error).font(.caption).foregroundStyle(.red)}
                    }.disabled(row.error != nil)
                }
                if rows.isEmpty{Text("暂无已保存槽位。可返回上一页保存人物或行程。")}
                Button("生成备份并存到文件（\(selectedAddresses.count)项）"){exportSelected()}.disabled(selectedAddresses.isEmpty)
            }.glassRow()
        }
    }
    private var importForm:some View {
        Group {
            Section("选取备份") {
                Button("从“文件”选择JSON备份"){picker=true}
                Text("支持新版批量备份、旧版人物/行程槽JSON及原地图工作档。先校验，再预览目标；不会立即替换正在玩的行程。").font(.caption)
                if !sourceName.isEmpty{Text("来源："+sourceName).font(.caption).lineLimit(2)}
            }.glassRow()
            if let package {
                Section("勾选条目并指定目标槽") {
                    ForEach(package.addresses){address in
                        VStack(alignment:.leading,spacing:6) {
                            Toggle(package.title(at:address),isOn:selected(address))
                            Text("来源：\(address.kind.title)槽\(address.slot)").font(.caption)
                            if selection.contains(address) {
                                Picker("写入目标",selection:Binding(get:{destinations[address] ?? address.slot},set:{destinations[address]=$0})){
                                    ForEach(1...address.kind.count,id:\.self){slot in Text("\(address.kind.title)槽\(slot)").tag(slot)}
                                }
                                Text(targetDescription(address)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("校对并导入（\(selectedAddresses.count)项）"){prepareConfirmation()}.disabled(selectedAddresses.isEmpty)
                    Text("覆盖前会保存目标槽的原始文件。导入只改所选槽；之后在人物/行程页点击读取，才会应用到游戏。").font(.caption)
                }.glassRow()
            }
            Section("导入前的槽位备份") {
                ForEach(backups.prefix(20)){backup in
                    if let error=backup.error {Text("原始备份保留，无法读取："+error).font(.caption).foregroundStyle(.red)}
                    else{Button(backup.createdAt.formatted(date:.abbreviated,time:.shortened)+" · \(backup.overwritten)个原槽"){readBackup(backup.id)}}
                }
                if backups.isEmpty{Text("暂无覆盖记录。")}
                Text("选择后仍先进入预览，不会自动覆盖。原文件损坏时会报错并保留原始字节。").font(.caption)
            }.glassRow()
        }
    }
    private func selected(_ address:MeadowSlotAddress)->Binding<Bool>{Binding(get:{selection.contains(address)},set:{if $0{selection.insert(address)}else{selection.remove(address)}})}
    private func targetDescription(_ address:MeadowSlotAddress)->String {
        let target=MeadowSlotAddress(address.kind,destinations[address] ?? address.slot)
        guard let row=rows.first(where:{$0.address==target}) else{return "空槽，将新增。"}
        return "将覆盖："+row.title+(row.error==nil ? "":"（无法读取，原始文件将先备份）")
    }
    private func refresh(selectDefaults:Bool=false){
        working=true;let folder=directory
        Task {let result=await Task.detached(priority:.userInitiated){()->Result<([TransferSlotRow],[MeadowImportBackup]),Error> in
            do{let store=MeadowSlotStore(directory:folder);var result=[TransferSlotRow]()
                for kind in MeadowSlotKind.allCases{for slot in 1...kind.count {
                    let address=MeadowSlotAddress(kind,slot)
                    do{if kind == .profile{if let p=try store.profile(slot){result.append(.init(address:address,title:p.title,error:nil))}}else if let c=try store.campaign(slot){result.append(.init(address:address,title:c.title,error:nil))}}
                    catch{result.append(.init(address:address,title:"无法读取",error:error.localizedDescription))}
                }}
                return .success((result,try store.importBackups()))
            }catch{return .failure(error)}
        }.value
            working=false
            switch result{case .success(let data):rows=data.0;backups=data.1;if selectDefaults{selection=request.selection ?? Set(rows.filter{$0.error==nil}.map(\.address))};case .failure(let error):notice="目录读取失败，原文件保留："+error.localizedDescription}
        }
    }
    private func exportSelected(){
        let chosen=Set(selectedAddresses),folder=directory;working=true
        Task {let result=await Task.detached(priority:.userInitiated){()->Result<Data,Error> in do{return .success(try MeadowSlotStore(directory:folder).exportTransfer(chosen).encoded())}catch{return .failure(error)}}.value
            working=false
            switch result{case .success(let bytes):document=MeadowSaveDocument(data:bytes);filename="Meadow-存档备份-"+Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash));exporter=true;case .failure(let error):notice="未导出："+error.localizedDescription}
        }
    }
    private func readFile(_ url:URL){
        package=nil;selection=[];destinations=[:];sourceName=url.lastPathComponent;working=true
        Task {let result=await Task.detached(priority:.userInitiated){()->Result<MeadowSaveTransfer,Error> in
            let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
            do{return .success(try MeadowSaveTransfer.read(from:url))}catch{return .failure(error)}
        }.value
            working=false
            switch result{case .success(let data):acceptPreview(data);case .failure(let error):notice="文件未导入，槽位未改变："+error.localizedDescription}
        }
    }
    private func readBackup(_ id:String){
        let folder=directory;working=true;package=nil;selection=[];destinations=[:]
        Task {let result=await Task.detached(priority:.userInitiated){()->Result<MeadowSaveTransfer,Error> in do{return .success(try MeadowSlotStore(directory:folder).transferBeforeImport(id))}catch{return .failure(error)}}.value
            working=false;sourceName="导入前的本机备份"
            switch result{case .success(let data):acceptPreview(data);case .failure(let error):notice="原始备份保留，暂不能读取："+error.localizedDescription}
        }
    }
    private func acceptPreview(_ value:MeadowSaveTransfer){package=value;selection=Set(value.addresses);destinations=Dictionary(uniqueKeysWithValues:value.addresses.map{($0,$0.slot)});notice="校验通过：\(value.profiles.count)个人物、\(value.campaigns.count)份行程。请检查写入目标。"}
    private func prepareConfirmation(){
        let addresses=selectedAddresses,targets=addresses.map{MeadowSlotAddress($0.kind,destinations[$0] ?? $0.slot)}
        guard Set(targets).count==targets.count else{notice="目标槽重复，请给每个条目选择不同槽位。";return}
        let overwritten=targets.filter{t in rows.contains{$0.address==t}}.count
        confirmation="导入\(addresses.count)项，其中\(overwritten)个目标槽已有文件，将先备份再覆盖。\n"+zip(addresses,targets).map{source,target in "\(source.kind.title)槽\(source.slot) → \(target.kind.title)槽\(target.slot)"}.joined(separator:"\n")+"\n当前游戏行程不切换。"
        confirm=true
    }
    private func performImport(){
        guard let package else{return};let chosen=Set(selectedAddresses),mapping=Dictionary(uniqueKeysWithValues:chosen.map{($0,destinations[$0] ?? $0.slot)}),folder=directory
        working=true
        Task {let result=await Task.detached(priority:.userInitiated){()->Result<String,Error> in do{return .success(try MeadowSlotStore(directory:folder).importTransfer(package.selecting(chosen),destinations:mapping))}catch{return .failure(error)}}.value
            working=false
            switch result{case .success:notice="已导入\(chosen.count)个槽位。请回上一页点击读取；当前游戏未改变。";self.package=nil;selection=[];destinations=[:];refresh();case .failure(let error):notice="导入失败，恢复记录已保留："+error.localizedDescription;refresh()}
        }
    }
    private func isCancellation(_ error:Error)->Bool{let e=error as NSError;return e.domain==NSCocoaErrorDomain && e.code==NSUserCancelledError}
}
