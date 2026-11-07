import SwiftUI
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport
import MeadowClassroomSupport

struct MeadowTeacherDashboard:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    @State private var selectingNode=false
    @State private var fullPreview=false
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16){
                HStack {
                    Text("教师游戏后台 · v0.13.3").font(.title.bold())
                    Spacer();Text(game.externalConnected ? "公开屏幕已连接":"当前可在本机预览")
                }
                Text(game.message).foregroundStyle(.secondary)
                HStack {
                    Button("随机地图与新行程"){game.settings()}.disabled(game.busy || game.campaign?.engine.state.battle != nil)
                    Button("继续已保存行程"){game.restore()}.disabled(game.busy || game.campaign?.engine.state.battle != nil)
                    Button("保存"){game.operation(.save)}.disabled(!game.ready || game.busy)
                    Button("暂停 / 继续移动"){game.operation(.pauseOrResume)}.disabled(!game.ready || game.busy)
                }.buttonStyle(ClassroomButtonStyle())
                if let campaign=game.campaign {
                    HStack {
                        ForEach(campaign.engine.state.players){unit in
                            Button(unit.name){game.select(unit.id)}.tint(unit.id==campaign.selectedPlayerID ? .blue:.gray)
                        }
                        Spacer();Text("移动 \(Int(ceil(campaign.movementRemaining)))/\(Int(ceil(campaign.movementCapacity)))")
                    }.buttonStyle(.borderedProminent)
                    Toggle("选取地点进行后台编辑",isOn:$selectingNode).onChange(of:selectingNode){_,value in if value{game.project(.exploration)}}
                    HStack {
                        Text("投放镜头")
                        Button("缩小"){game.operation(.zoom(-1))}
                        Button("放大"){game.operation(.zoom(1))}
                        Button("←"){game.operation(.pan(CGPoint(x:60,y:0)))}
                        Button("→"){game.operation(.pan(CGPoint(x:-60,y:0)))}
                        Button("↑"){game.operation(.pan(CGPoint(x:0,y:60)))}
                        Button("↓"){game.operation(.pan(CGPoint(x:0,y:-60)))}
                    }.buttonStyle(.bordered).disabled(!game.ready || game.busy)
                    if game.renderer != nil && !fullPreview {
                        TeacherGamePreview(game:game,selectingNode:selectingNode,tracksScroll:true).aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:14))
                        Button("全屏查看公开游戏界面"){fullPreview=true}.buttonStyle(ClassroomButtonStyle(primary:true))
                    }
                    Text(selectingNode ? "点击上方游戏画面选择地点，修改表单只在教师端出现。":"拖动地图平移视野，双指缩放；点击道路移动人物。").font(.callout)
                    if let id=game.selectedNode {Text("后台选中：\(id) · \(campaign.engine.state.map.nodes.first{$0.id==id}?.name ?? "地点")").font(.callout.bold())}
                    HStack {
                        Button("投放探索地图"){game.project(.exploration)}
                        Button("投放选中怪物预览"){if let id=game.selectedNode{game.project(.encounter(id))}}.disabled(game.selectedNode==nil || campaign.engine.state.battle != nil)
                        Button("行囊与装备"){game.operation(.inventory)}.disabled(!campaign.canManageInventory || !game.ready)
                        Button("交互当前地点"){game.operation(.interact)}.disabled(!game.ready || game.busy || campaign.isMoving)
                    }.buttonStyle(ClassroomButtonStyle(primary:true))
                    if campaign.engine.state.battle != nil {
                        battleControls(campaign)
                    }
                    Divider()
                    Text("教师权限 · 仅后台").font(.headline)
                    HStack {
                        Button("编辑选中地点"){if let id=game.selectedNode{game.operation(.editNode(id))}}.disabled(game.selectedNode==nil || campaign.travel != nil || campaign.engine.state.battle != nil)
                        Button("购买移动 / 手动补满"){game.operation(.refill)}.disabled(campaign.isMoving || campaign.engine.state.battle != nil)
                        Button("调整生命与资源"){game.editResources()}.disabled(game.busy)
                        Button("奖励10金币"){game.award()}.disabled(game.busy)
                        Button("队伍与成员"){game.operation(.team)}.disabled(game.busy)
                        Button("路线与结算"){game.operation(.route)}.disabled(game.busy)
                    }.buttonStyle(ClassroomButtonStyle())
                    Text("节点总数、分类、滑块、种子与职业配置均在后台设置。编辑模式的选择不会投放到游戏画面。").font(.caption).foregroundStyle(.secondary)
                }else{
                    ContentUnavailableView("等待后台生成行程",systemImage:"map",description:Text("先设置随机地图，再开始投放。"))
                }
            }.padding(24)
        }.background(GameTheme.background).foregroundStyle(GameTheme.ink)
        .fullScreenCover(isPresented:$fullPreview){
            ZStack(alignment:.topTrailing){
                TeacherGamePreview(game:game,selectingNode:selectingNode).ignoresSafeArea()
                HStack {
                    if !game.surface.acceptsMapInput || game.surface != .exploration {
                        Button("收起预览"){game.project(.exploration)}.disabled(game.campaign?.engine.state.battle != nil || game.surface == .book)
                    }
                    Button("返回教师后台"){fullPreview=false}
                }.buttonStyle(.borderedProminent).padding()
            }
        }

        .onChange(of:fullPreview){_,value in game.localOutputPreview=value}
    }
    private func battleControls(_ c:MeadowCampaignSession)->some View {
        VStack(alignment:.leading,spacing:10){
            Text("战斗操作 · "+(c.engine.state.battle?.current.flatMap{c.engine.state.units[$0]?.name} ?? "动作演出中")).font(.headline)
            Button("暂停 / 继续战斗"){game.toggleBattlePause()}.disabled(game.busy)
            Picker("目标",selection:$game.selectedTarget){
                ForEach(c.engine.state.units.values.filter{$0.kind == .player || c.engine.state.battle?.queue.contains($0.id)==true}.sorted{$0.id<$1.id}){u in Text(u.name).tag(u.id)}
            }.pickerStyle(.menu)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:150))],spacing:10){
                ForEach(game.actions,id:\.rawValue){action in
                    Button(action.title){game.battle(action)}.buttonStyle(.borderedProminent)
                        .disabled(!game.canUse(action)).onHover{game.focus($0 ? action:nil)}
                }
                ForEach([PartyAction.smallPotion,.largePotion,.shieldPotion,.revivalStone],id:\.rawValue){a in Button(a.title){game.battle(a)}.disabled(!game.canUse(a))}
                Button("结束当前行动"){game.battle(.endTurn)}.disabled(!game.canUse(.endTurn))
            }
        }.padding().background(.white.opacity(0.8),in:RoundedRectangle(cornerRadius:14))
    }
}

private struct TeacherGamePreview:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    let selectingNode:Bool
    var tracksScroll=false
    @State private var previewID=UUID()
    var body:some View {
        PublicSurface(model:TeacherSession.shared.display,game:game,teacherPreview:true)
            .overlay {
                MeadowTeacherMapInput(canBegin:game.canBeginMapGesture,
                    tap:{game.canvasTap($0,selectingNode:selectingNode)},
                    pan:game.canvasPan,zoom:{game.canvasZoom($0,anchor:$1)})
            }
            .onScrollVisibilityChange(threshold:0.05){visible in if tracksScroll{game.previewVisibility(previewID,visible:visible)}}
            .onAppear{game.previewVisibility(previewID,visible:true)}
            .onDisappear{game.previewVisibility(previewID,visible:false)}
    }
}
