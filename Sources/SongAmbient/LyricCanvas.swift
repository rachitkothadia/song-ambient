import SwiftUI
import AppKit
import AmbientCore

struct LyricCanvas:View{
    @ObservedObject var model:AppModel
    @ObservedObject var music:MusicWatcher
    @ObservedObject var audio:AudioCapture
    @ObservedObject var lyrics:LyricsService
    var transparent=false
    var preview=false
    private static let demo:WordPresentation={
        let words=["Yeh","raat","roshni","aur","hum","Music","moves","through","the","stars","Dil","ki","dhun","mein","aaj","khoye","Har","lafz","ek","naya","sitara","ban","jaaye","here"].enumerated().map{LyricWord(time:Double($0.offset),end:Double($0.offset+1),text:$0.element,id:$0.offset)}
        return WordPresentation(lines:[LyricLine(time:0,end:24,text:"Authored word timing demo",id:0,words:words)],seed:9527)
    }()
    var body:some View{
        ZStack{
            if !transparent{
                Color(red:0.006,green:0.009,blue:0.022)
                if model.prefs.lyricStyle.showsArtwork,let artwork=music.artwork{
                    GeometryReader{g in Image(nsImage:artwork).resizable().scaledToFill().frame(width:g.size.width,height:g.size.height).clipped().blur(radius:65).opacity(0.24)}.allowsHitTesting(false)
                    Color.black.opacity(0.4)
                }
            }
            TimelineView(.animation(minimumInterval:1.0/60,paused:(!music.playing && !model.lyricsDemo) || (preview && model.stageVisible))){timeline in
                let presentation=model.lyricsDemo ? Self.demo:lyrics.presentation
                let clock=model.lyricsDemo ? timeline.date.timeIntervalSince(model.demoStart).truncatingRemainder(dividingBy:24):music.currentTime(at:timeline.date)+model.prefs.lyricsOffset
                let frame=presentation.frame(at:clock,duration:model.lyricsDemo ? 24:music.duration)
                let renderer=WordCanvasRenderer(presentation:presentation,frame:frame,style:model.prefs.lyricStyle,font:model.prefs.lyricFont,fontSize:model.prefs.lyricSize*(preview ? 0.62:1),highlight:model.prefs.lyricAutoColor ? Self.readable(model.colors[0]):Color(hex:model.prefs.lyricHighlight),primary:Color(hex:model.prefs.lyricText),secondary:Color(hex:model.prefs.lyricSecondary),wall:timeline.date.timeIntervalSinceReferenceDate,bass:audio.bass,transparent:transparent)
                Canvas(rendersAsynchronously:true){context,size in renderer.draw(context:context,size:size)}
            }
            if lyrics.presentation.tokens.isEmpty && !model.lyricsDemo && !transparent{
                VStack(spacing:14){OrbitMark().frame(width:42,height:42).foregroundStyle(.cyan);Text(lyrics.loading ? "Finding the words…":"Your song, in the stars.").font(.system(size:preview ? 18:30,weight:.light,design:.rounded));Text(lyrics.loading ? "Preparing word motion":"Play a track in the selected music app or import timed lyrics.").font(.system(size:preview ? 10:13)).foregroundStyle(.secondary)}
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped().accessibilityElement(children:.ignore).accessibilityLabel(accessibilityWord)
    }
    private var accessibilityWord:String{
        if model.lyricsDemo{return "Authored word timing demo"}
        let frame=lyrics.presentation.frame(at:music.position+model.prefs.lyricsOffset,duration:music.duration)
        return frame.index.map{lyrics.presentation.tokens[$0].text} ?? "Waiting for a lyric word"
    }
    private static func readable(_ color:Color)->Color{
        guard let rgb=NSColor(color).usingColorSpace(.sRGB) else{return .cyan}
        return Color(nsColor:NSColor(hue:rgb.hueComponent,saturation:min(0.42,rgb.saturationComponent),brightness:max(0.97,rgb.brightnessComponent),alpha:1))
    }
}

private struct WordCanvasRenderer{
    let presentation:WordPresentation
    let frame:WordPlaybackFrame
    let style:LyricStyle
    let font:LyricFont
    let fontSize:Double
    let highlight:Color,primary:Color,secondary:Color
    let wall:Double,bass:Double
    let transparent:Bool
    private func random(_ value:Int)->Double{let x=sin(Double(value)*127.1+311.7)*43758.5453;return x-floor(x)}
    func draw(context:GraphicsContext,size:CGSize){
        let w=size.width,h=size.height
        let constellation=style == .constellation,web=style == .web,branches=style == .branches
        if !transparent && (constellation || web || style == .ship){
            let sky=(0..<110).map{CGPoint(x:random($0*3)*w,y:random($0*3+1)*h)}
            for star in 0..<110{
                let point=sky[star],radius=0.35+random(star*3+2)*1.1
                let alpha=0.12+0.22*(0.5+0.5*sin(wall*0.35+Double(star)))
                context.fill(Path(ellipseIn:CGRect(x:point.x,y:point.y,width:radius,height:radius)),with:.color(primary.opacity(alpha)))
                if constellation && star%5==0{
                    var neighbor=sky[(star+1)%sky.count]
                    for offset in 2...24{let candidate=sky[(star+offset)%sky.count];if hypot(candidate.x-point.x,candidate.y-point.y)<hypot(neighbor.x-point.x,neighbor.y-point.y){neighbor=candidate}}
                    if hypot(neighbor.x-point.x,neighbor.y-point.y)<min(w,h)*0.18{
                        var path=Path();path.move(to:point);path.addLine(to:neighbor)
                        context.stroke(path,with:.color(secondary.opacity(0.1)),lineWidth:0.45)
                    }
                }
            }
        }
        guard let active=frame.index,presentation.tokens.indices.contains(active) else{return}
        let ease=1-pow(1-min(1,max(0,frame.entrance)),3)
        let lower=max(0,active-3),upper=min(presentation.tokens.count-1,active+3)
        var visible=Array(lower...upper)
        if branches{let root=active/7*7;visible=Array(root...min(root+6,presentation.tokens.count-1))}
        if style == .visual{visible=Array(max(0,active-1)...active)}
        if style == .ship{visible=Array(max(0,active-2)...min(presentation.tokens.count-1,active+1))}
        func position(_ index:Int)->CGPoint{
            let point=presentation.stars[index],delta=Double(index-active)
            switch style{
            case .constellation:
                if index==active,index>0{
                    let from=presentation.stars[index-1],dx=point.x-from.x,dy=point.y-from.y
                    let length=max(0.01,hypot(dx,dy)),bend=sin(ease * .pi)*0.055
                    let x=min(0.86,max(0.14,from.x+dx*ease-dy/length*bend))
                    let y=min(0.75,max(0.23,from.y+dy*ease+dx/length*bend))
                    return CGPoint(x:x*w,y:y*h)
                }
                return CGPoint(x:point.x*w,y:point.y*h)
            case .branches:
                let tree=[StarPoint(x:0.5,y:0.25),StarPoint(x:0.27,y:0.46),StarPoint(x:0.73,y:0.46),StarPoint(x:0.14,y:0.7),StarPoint(x:0.39,y:0.7),StarPoint(x:0.61,y:0.7),StarPoint(x:0.86,y:0.7)]
                let p=tree[index%7];return CGPoint(x:p.x*w,y:p.y*h)
            case .web:
                let angle=Double(index%8)*Double.pi/4-Double.pi/2
                if index==active{return CGPoint(x:w*0.5,y:h*0.48)}
                return CGPoint(x:w*(0.5+cos(angle)*0.32),y:h*(0.48+sin(angle)*0.25))
            case .ship:
                let angle=atan2(point.y-0.5,point.x-0.5)
                let distance=index==active ? (1-ease)*0.45:index<active ? min(0.6,0.25+abs(delta)*0.12+ease*0.12):0.48
                return CGPoint(x:w*(0.5+cos(angle)*distance),y:h*(0.49+sin(angle)*distance))
            case .fisheye,.fisheyeVisual:
                let angle=(delta+1-ease)*0.58
                return CGPoint(x:w*(0.5+sin(angle)*0.42),y:h*(0.44+(1-cos(angle))*0.32))
            case .visual:return CGPoint(x:w*0.5,y:h*0.49)
            case .code:return CGPoint(x:w*0.19,y:h*0.48+delta*max(30,fontSize*0.92))
            case .codeVisual:
                if index==active{return CGPoint(x:w*0.5,y:h*0.48)}
                return CGPoint(x:w*(delta<0 ? 0.23:0.77),y:h*(0.35+Double(abs(index-active)-1)*0.12))
            }
        }
        if constellation || web || branches{
            for (offset,index) in visible.enumerated(){
                let p=position(index)
                if branches{
                    let local=index%7
                    if local>0{let parent=index-local+(local-1)/2;link(from:position(parent),to:p,context:context,alpha:index<=active ? 0.55:0.09,progress:index==active ? ease:1)}
                }else{
                    let neighbors=visible.filter{$0 != index}.sorted{a,b in hypot(position(a).x-p.x,position(a).y-p.y)<hypot(position(b).x-p.x,position(b).y-p.y)}
                    for other in neighbors.prefix(web ? 4:2) where other<index{link(from:position(other),to:p,context:context,alpha:web ? 0.17:0.2,progress:1)}
                    if constellation && offset>0,index<=active{link(from:position(visible[offset-1]),to:p,context:context,alpha:index==active ? 0.7:0.33,progress:index==active ? ease:1)}
                }
            }
        }
        if style == .visual || style == .codeVisual{
            let center=CGPoint(x:w*0.5,y:h*0.49),radius=min(w,h)*(0.15+ease*0.07+bass*0.025)
            context.stroke(Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)),with:.color(highlight.opacity((1-ease)*0.35+0.045)),lineWidth:0.8)
            if style == .codeVisual{
                let box=CGRect(x:w*0.17,y:h*0.26,width:w*0.66,height:h*0.44)
                context.stroke(Path(roundedRect:box,cornerRadius:12),with:.color(highlight.opacity(0.2)),style:StrokeStyle(lineWidth:0.8,dash:[7,13]))
            }
        }
        for index in visible{
            let current=index==active,p=position(index),delta=abs(index-active)
            var scale=current ? 1.12+(1-ease)*0.12+bass*0.025:0.43
            var opacity=current ? 1.0:index<active ? max(0.13,0.52-Double(delta)*0.1):0.16
            if style == .visual{scale=current ? 1.4-(1-ease)*0.22:1.7+ease*0.15;opacity=current ? ease:0.16*(1-ease)}
            if style == .fisheye || style == .fisheyeVisual{scale=0.25+1.1*pow(max(0,cos((Double(index-active)+1-ease)*0.58)),3);opacity *= max(0.2,scale)}
            if style == .ship{scale=current ? 0.35+ease*0.95:0.35;opacity=current ? max(0.15,ease):0.12}
            let mono=style == .code || style == .codeVisual
            let text=presentation.tokens[index].text
            let prefix=style == .code ? String(format:"%03d  ",index+1):""
            let shown=style == .codeVisual && current ? "{ \(text) }":prefix+text
            let safeWidth=style == .code ? w*0.69:min(w*0.7,2*min(p.x-w*0.035,w*0.965-p.x))
            var point=p
            if constellation || branches || web{point.y+=current ? 17:10}
            drawWord(shown,at:point,size:fontSize*scale,maxWidth:max(20,safeWidth),canvasHeight:h,color:(current ? highlight:index<active ? primary:secondary).opacity(min(1,opacity)),mono:mono,current:current,anchor:style == .code ? .leading:(constellation || branches || web ? .top:.center),context:context)
            if constellation || branches || web{
                let radius=current ? 4.4+bass*1.5:1.8
                var layer=context;if current{layer.addFilter(.shadow(color:highlight.opacity(0.7),radius:10))}
                layer.fill(Path(ellipseIn:CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2)),with:.color((current ? highlight:secondary).opacity(current ? 1:0.65)))
                if current{
                    let ring=8+ease*17
                    layer.stroke(Path(ellipseIn:CGRect(x:p.x-ring,y:p.y-ring,width:ring*2,height:ring*2)),with:.color(highlight.opacity((1-ease)*0.7+0.08)),lineWidth:0.7)
                    var cross=Path();cross.move(to:CGPoint(x:p.x-8,y:p.y));cross.addLine(to:CGPoint(x:p.x+8,y:p.y));cross.move(to:CGPoint(x:p.x,y:p.y-8));cross.addLine(to:CGPoint(x:p.x,y:p.y+8));layer.stroke(cross,with:.color(highlight.opacity(0.75)),lineWidth:0.55)
                }
            }
            if style == .code && current{
                var caret=Path();caret.move(to:CGPoint(x:p.x,y:p.y+fontSize*0.7));caret.addLine(to:CGPoint(x:p.x+fontSize*1.6,y:p.y+fontSize*0.7));context.stroke(caret,with:.color(highlight.opacity(0.7)),lineWidth:1)
            }
        }
    }
    private func link(from:CGPoint,to:CGPoint,context:GraphicsContext,alpha:Double,progress:Double){
        var path=Path();path.move(to:from);path.addLine(to:CGPoint(x:from.x+(to.x-from.x)*progress,y:from.y+(to.y-from.y)*progress))
        context.stroke(path,with:.color(highlight.opacity(alpha)),lineWidth:0.65)
    }
    private func drawWord(_ word:String,at point:CGPoint,size:Double,maxWidth:Double,canvasHeight:CGFloat,color:Color,mono:Bool,current:Bool,anchor:UnitPoint,context:GraphicsContext){
        func text(_ size:Double)->Text{Text(word).font(mono && font == .sfPro ? .system(size:size,weight:current ? .semibold:.regular,design:.monospaced):font.font(size:size,weight:current ? .semibold:.regular)).foregroundColor(color)}
        let measured=context.resolve(text(size)).measure(in:CGSize(width:10000,height:10000))
        let fitted=size*min(1,maxWidth/max(1,measured.width))
        let height=context.resolve(text(fitted)).measure(in:CGSize(width:10000,height:10000)).height
        var position=point,chosenAnchor=anchor
        if anchor.y==0 && point.y+height>canvasHeight-8 {chosenAnchor = .bottom;position.y-=27}
        if chosenAnchor.y==0{position.y=max(8,min(position.y,canvasHeight-height-8))}
        else if chosenAnchor.y==1{position.y=max(height+8,min(position.y,canvasHeight-8))}
        else{position.y=max(height/2+8,min(position.y,canvasHeight-height/2-8))}
        var layer=context
        if current{layer.addFilter(.shadow(color:highlight.opacity(0.26),radius:18))}
        layer.draw(text(fitted),at:position,anchor:chosenAnchor)
    }
}
