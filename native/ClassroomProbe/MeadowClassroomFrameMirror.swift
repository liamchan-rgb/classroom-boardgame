import SwiftUI
import UIKit

/// Only the game controller supplies pixels. No teacher root, permission sheet,
/// notes or controls can be included. No second campaign/renderer is created.
@MainActor final class MeadowFrameMirror:ObservableObject {
    @Published var image:UIImage?
}
struct MeadowTeacherMirror:View {
    @ObservedObject var mirror:MeadowFrameMirror
    var body:some View {
        ZStack {
            Color.black
            if let image=mirror.image {Image(uiImage:image).resizable().interpolation(.none).scaledToFit()}
            else{Text("正在同步游戏画面…").foregroundStyle(.white)}
        }
    }
}
