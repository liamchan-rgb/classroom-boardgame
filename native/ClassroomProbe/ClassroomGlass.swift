import SwiftUI
import UIKit

/// A plain UIKit text field for teacher forms. SwiftUI's TextField lost focus in the
/// frequently refreshed teacher sheets (live previews, timers); a UITextField keeps its own
/// first-responder state, so typing and the Chinese input method work reliably.
struct ClassroomTextField:UIViewRepresentable {
    var placeholder:String
    @Binding var text:String
    var limit:Int=40
    var keyboard:UIKeyboardType = .default
    var alignment:NSTextAlignment = .natural
    /// Called on Return/Enter (the field keeps focus so the next value can be typed straight away).
    var onSubmit:(()->Void)?=nil
    /// Take the keyboard as soon as the field appears.
    var autoFocus=false
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIView(context:Context)->UITextField {
        let field=UITextField()
        field.placeholder=placeholder;field.text=text;field.keyboardType=keyboard;field.textAlignment=alignment
        field.borderStyle = .none;field.clearButtonMode = .whileEditing;field.returnKeyType = .done
        field.font = .systemFont(ofSize:17,weight:.medium);field.textColor = .label
        field.autocorrectionType = .no;field.spellCheckingType = .no
        if onSubmit != nil {field.returnKeyType = .go}
        if autoFocus {DispatchQueue.main.asyncAfter(deadline:.now()+0.35){field.becomeFirstResponder()}}
        field.setContentHuggingPriority(.defaultLow,for:.horizontal)
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        field.delegate=context.coordinator
        field.addTarget(context.coordinator,action:#selector(Coordinator.changed(_:)),for:.editingChanged)
        return field
    }
    func updateUIView(_ field:UITextField,context:Context) {
        context.coordinator.parent=self
        // Never overwrite while the user is composing (marked Chinese input) or editing.
        if !field.isFirstResponder,field.text != text {field.text=text}
        field.placeholder=placeholder
    }
    final class Coordinator:NSObject,UITextFieldDelegate {
        var parent:ClassroomTextField
        init(_ parent:ClassroomTextField){self.parent=parent}
        @objc func changed(_ field:UITextField) {
            guard field.markedTextRange==nil else{return}
            var value=field.text ?? ""
            if value.count>parent.limit {value=String(value.prefix(parent.limit));field.text=value}
            parent.text=value
        }
        func textFieldDidEndEditing(_ field:UITextField){parent.text=String((field.text ?? "").prefix(parent.limit))}
        func textFieldShouldReturn(_ field:UITextField)->Bool {
            if let submit=parent.onSubmit {
                parent.text=field.text ?? "";submit()
                DispatchQueue.main.async{field.text=self.parent.text}
                return false
            }
            field.resignFirstResponder();return true
        }
    }
}

/// Frosted-glass field chrome with a leading icon, used for every typed input.
struct GlassField:View {
    var icon:String
    var placeholder:String
    @Binding var text:String
    var limit:Int=40
    var keyboard:UIKeyboardType = .default
    var body:some View {
        HStack(spacing:10){
            Image(systemName:icon).font(.system(size:17,weight:.semibold)).foregroundStyle(GameTheme.primary).frame(width:22)
            ClassroomTextField(placeholder:placeholder,text:$text,limit:limit,keyboard:keyboard).frame(height:40)
        }
        .padding(.horizontal,12)
        .background(GlassFill.field,in:RoundedRectangle(cornerRadius:12,style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:12,style:.continuous).stroke(.white.opacity(0.55),lineWidth:1))
    }
}

/// The shared backdrop behind teacher sheets: a soft meadow wash so the frosted panels read as glass.
struct GlassBackdrop:View {
    var body:some View {
        ZStack{
            LinearGradient(colors:[Color(red:0.80,green:0.90,blue:0.86),Color(red:0.70,green:0.82,blue:0.90),Color(red:0.86,green:0.84,blue:0.74)],startPoint:.topLeading,endPoint:.bottomTrailing)
            // Soft colour pools drawn as radial gradients: same look as blurred blobs, no per-frame blur pass.
            RadialGradient(colors:[Color(red:0.55,green:0.78,blue:0.62).opacity(0.55),.clear],center:UnitPoint(x:0.15,y:0.12),startRadius:0,endRadius:520)
            RadialGradient(colors:[Color(red:0.98,green:0.80,blue:0.55).opacity(0.45),.clear],center:UnitPoint(x:0.88,y:0.9),startRadius:0,endRadius:520)
        }.ignoresSafeArea()
    }
}

extension View {
    /// Frosted glass panel: material fill, hairline highlight and a soft lift.
    func glassPanel(radius:CGFloat=18,padding:CGFloat=14)->some View {
        self.padding(padding)
            .background(GlassFill.panel,in:RoundedRectangle(cornerRadius:radius,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).stroke(LinearGradient(colors:[.white.opacity(0.7),.white.opacity(0.15)],startPoint:.top,endPoint:.bottom),lineWidth:1))
    }
    /// A sheet whose content sits on glass over the meadow wash.
    func glassSheet()->some View {
        self.scrollContentBackground(.hidden).background(GlassBackdrop())
    }
}

/// Icon-first glass button: the symbol carries the meaning; the caption is short (or omitted).
struct GlassIconButtonStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var tint:Color=GameTheme.primary
    var prominent=false
    func makeBody(configuration:Configuration)->some View {
        configuration.label
            .labelStyle(GlassLabelStyle())
            .padding(.horizontal,12).frame(minWidth:48,minHeight:48)
            .foregroundStyle(prominent ? Color.white:tint)
            .background {
                if prominent {RoundedRectangle(cornerRadius:14,style:.continuous).fill(tint.opacity(enabled ? 0.9:0.4))}
                else {RoundedRectangle(cornerRadius:14,style:.continuous).fill(GlassFill.button)}
            }
            .overlay(RoundedRectangle(cornerRadius:14,style:.continuous).stroke(.white.opacity(prominent ? 0.35:0.6),lineWidth:1))
            .scaleEffect(configuration.isPressed ? 0.95:1)
            .opacity(enabled ? 1:0.45)
            .animation(.spring(response:0.25,dampingFraction:0.7),value:configuration.isPressed)
    }
}
/// Icon above a small caption.
struct GlassLabelStyle:LabelStyle {
    func makeBody(configuration:Configuration)->some View {
        VStack(spacing:3){
            configuration.icon.font(.system(size:19,weight:.semibold))
            configuration.title.font(.system(size:11,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
/// A compact pill: icon plus a number or two-character word.
struct GlassChip:View {
    var icon:String
    var text:String
    var tint:Color=GameTheme.primary
    var body:some View {
        HStack(spacing:5){
            Image(systemName:icon).font(.system(size:13,weight:.bold)).foregroundStyle(tint)
            Text(text).font(.system(size:14,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(GameTheme.ink)
        }
        .padding(.horizontal,10).padding(.vertical,6)
        .background(GlassFill.field,in:Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.6),lineWidth:1))
    }
}
/// Section header for glass panels: an icon and one or two words.
struct GlassHeader:View {
    var icon:String
    var title:String
    var body:some View {
        Label(title,systemImage:icon).font(.system(size:15,weight:.bold)).foregroundStyle(GameTheme.ink)
    }
}

extension View {
    /// Frosted rows for teacher forms (use with `glassSheet()`).
    func glassRow()->some View {listRowBackground(Rectangle().fill(GlassFill.panel))}
}
/// Static "frosted" fills. Live material blur (backdrop filters) re-renders every frame while the game
/// preview animates in the same window and made the teacher iPad stutter, so glass is faked with
/// translucent white gradients over the soft, static backdrop.
enum GlassFill {
    static let panel=LinearGradient(colors:[.white.opacity(0.72),.white.opacity(0.52)],startPoint:.top,endPoint:.bottom)
    static let button=LinearGradient(colors:[.white.opacity(0.82),.white.opacity(0.62)],startPoint:.top,endPoint:.bottom)
    static let field=Color.white.opacity(0.66)
}
