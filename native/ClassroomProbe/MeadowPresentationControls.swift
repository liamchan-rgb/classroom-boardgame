import SwiftUI

/// Teacher-only controls, deliberately outside PublicSurface.
struct MeadowPresentationControls:View {
    @ObservedObject var display:PublicDisplayModel
    @State private var preview=false
    var body:some View {
        HStack {
            Toggle("公开端使用 Meadow 画面",isOn:$display.meadowPresentation).fixedSize()
            Text("教师操作布局保留；绘本继续显示原页。").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("预览公开画面") { preview=true }.buttonStyle(ClassroomButtonStyle())
        }
        .fullScreenCover(isPresented:$preview) {
            ZStack(alignment:.topTrailing) {
                PublicSurface(model:display).ignoresSafeArea()
                Button("返回教师操作") { preview=false }.buttonStyle(.borderedProminent).padding()
            }
        }
    }
}
