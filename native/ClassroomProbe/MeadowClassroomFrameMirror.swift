import SwiftUI
import UIKit

/// Both layers originate in the one clean game controller, never the teacher root.
struct MeadowTeacherPreviewFrame {
    let map:CGImage?
    let mapRect:CGRect
    let overlay:UIImage?
    let background:UIColor
}
@MainActor final class MeadowFrameMirror:ObservableObject {
    @Published var frame:MeadowTeacherPreviewFrame?
}
struct MeadowTeacherMirror:View {
    @ObservedObject var mirror:MeadowFrameMirror
    var body:some View {
        ZStack(alignment:.topLeading) {
            if let frame=mirror.frame {
                Color(uiColor:frame.background)
                if let map=frame.map {
                    Image(decorative:map,scale:1).resizable().interpolation(.none)
                        .frame(width:frame.mapRect.width,height:frame.mapRect.height)
                        .position(x:frame.mapRect.midX,y:frame.mapRect.midY)
                }
                if let overlay=frame.overlay {Image(uiImage:overlay).resizable().interpolation(.none)}
            }else{Color.black;Text("正在同步游戏画面…").foregroundStyle(.white)}
        }
    }
}
