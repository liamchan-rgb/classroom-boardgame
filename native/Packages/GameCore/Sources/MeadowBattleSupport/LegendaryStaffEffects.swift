import Foundation
/// Geometry shared by the device renderer and offline art review. No game state.
public struct StaffEffectSample:Codable {
    public let gem:PartyPoint,impact:PartyPoint,ground:PartyPoint
    public let charge:Double,impactPower:Double,burstRadius:Double,scale:Double
    public let head:PartyPoint?
    public let trail:[PartyPoint],motes:[PartyParticle],rays:[PartySlash]
    public let naturalTwenty:Bool
}
extension LegendaryStaffRig {
    public static func effect(age:Double,foot:PartyPoint,target:PartyPoint,groundY:Double,scale:Double,naturalTwenty:Bool=false)->StaffEffectSample {
        func world(_ p:PartyPoint)->PartyPoint { PartyPoint(foot.x+(p.x-123)*scale,foot.y+(p.y-214)*scale) }
        let t=artTime(age:age),gem=world(Self.gem(progress:progress(age:age)))
        let charge=PartyVisual.pulse(t,0.42,0.91,1.10)
        let start=world(Self.gem(progress:progress(age:releaseAge)))
        func path(_ u:Double)->PartyPoint {
            PartyPoint(start.x+(target.x-start.x)*u,start.y+(target.y-start.y)*u-40*scale/0.9*sin(Double.pi*u))
        }
        var head:PartyPoint?,trail:[PartyPoint]=[],motes:[PartyParticle]=[],rays:[PartySlash]=[]
        if age>=releaseAge && age<=impactAge {
            let u=(age-releaseAge)/(impactAge-releaseAge)
            head=path(u);trail=(0...7).map { path(max(0,u-Double(7-$0)*0.045)) }
        }
        if t>0.42 && age<releaseAge {
            for i in 0..<3 {
                let phase=t*6.5+Double(i)*Double.pi*2/3
                motes.append(PartyParticle(id:i,x:gem.x+cos(phase)*(11+Double(i)*3)*scale,y:gem.y+sin(phase)*(7+Double(i)*2)*scale,size:(4+Double(i)*2)*scale,alpha:charge*0.75,angle:phase))
            }
        }
        let hit=age-impactAge,power=PartyVisual.pulse(hit,-0.02,0.035,0.46)*(naturalTwenty ? 1.35:1)
        if hit>=0 && hit<1.15 {
            for i in 0..<34 {
                let delay=Double(i%6)*0.012,local=hit-delay
                guard local>=0 else { continue }
                let angle=Double(i)*2.3999632297
                let vx=(cos(angle)*145+35)*scale,vy=(-40-Double(i%7)*10)*scale,g=2400*scale
                let floor=max(target.y,groundY-2*scale),dy=floor-target.y
                let fall=(-vy+sqrt(vy*vy+2*g*dy))/g
                let bounce=max(0,local-fall)
                let y=local<=fall ? target.y+vy*local+g*local*local/2:floor-min(16*scale,max(0,105*scale*bounce-g*bounce*bounce/2))
                motes.append(PartyParticle(id:10+i,x:target.x+vx*min(local,fall)+vx*0.3*bounce,y:y,size:Double(i%5==0 ? 6:3)*scale,alpha:(1-PartyVisual.smooth((local-0.18)/0.40))*min(1,local/0.025),angle:angle+local*2))
            }
            let size=(22+hit*120)*scale*(naturalTwenty ? 1.35:1)
            for k in 0..<3 {
                let radius=size*(0.7+Double(k)*0.38)
                let points=(0...20).map { j -> PartyPoint in
                    let degrees=15.0+Double(k)*24.0+hit*90.0
                    let a=(degrees+Double(j)*4.75)*Double.pi/180.0
                    return PartyPoint(target.x+cos(a)*radius,target.y+sin(a)*radius*0.5)
                }
                rays.append(PartySlash(points:points,alpha:min(1,power)*0.7))
            }
        }
        return StaffEffectSample(gem:gem,impact:target,ground:PartyPoint(target.x,groundY),charge:charge,impactPower:power,burstRadius:max(0,22+hit*120)*scale*(naturalTwenty ? 1.35:1),scale:scale,head:head,trail:trail,motes:motes,rays:rays,naturalTwenty:naturalTwenty)
    }
}
