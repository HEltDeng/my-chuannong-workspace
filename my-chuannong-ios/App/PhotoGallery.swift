import SwiftUI
import UIKit

struct PhotoGallery:View {
    let paths:[String]
    @State var index:Int
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            TabView(selection:$index){ForEach(Array(paths.enumerated()),id:\.offset){position,path in ZoomablePhoto(path:path).tag(position)}}.tabViewStyle(.page(indexDisplayMode:.never)).background(.black).ignoresSafeArea(edges:.bottom)
                .navigationTitle("\(index+1) / \(paths.count)").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("关闭大图"){dismiss()}};ToolbarItemGroup(placement:.bottomBar){Button("上一张"){index=max(0,index-1)}.disabled(index==0);Spacer();Button("下一张"){index=min(paths.count-1,index+1)}.disabled(index>=paths.count-1)}}
        }.preferredColorScheme(.dark)
    }
}
struct ZoomablePhoto:UIViewRepresentable {
    let path:String
    func makeUIView(context:Context)->PhotoScrollView{PhotoScrollView()}
    func updateUIView(_ view:PhotoScrollView,context:Context){view.load(path)}
    static func dismantleUIView(_ view:PhotoScrollView,coordinator:()){view.cancel()}
}
@MainActor final class PhotoScrollView:UIScrollView,UIScrollViewDelegate {
    private let photo=UIImageView()
    private let label=UILabel()
    private var current:String?
    private var loading:Task<Void,Never>?
    private var lastSize=CGSize.zero
    override init(frame:CGRect){super.init(frame:frame);delegate=self;minimumZoomScale=1;maximumZoomScale=6;photo.contentMode = .scaleAspectFit;photo.isAccessibilityElement=true;photo.accessibilityLabel="完整图片，可双指缩放";addSubview(photo);label.textColor = .lightGray;label.textAlignment = .center;label.font = .preferredFont(forTextStyle:.footnote);label.numberOfLines=0;addSubview(label);let double=UITapGestureRecognizer(target:self,action:#selector(toggleZoom));double.numberOfTapsRequired=2;addGestureRecognizer(double)}
    required init?(coder:NSCoder){fatalError("init(coder:) is not used")}
    func cancel(){loading?.cancel();loading=nil}
    func load(_ path:String){guard current != path else{return};cancel();current=path;photo.image=nil;label.text="正在加载图片…";setZoomScale(1,animated:false)
        loading=Task{
            do{
                let data:Data
                if path.hasPrefix("data:image/"),let encoded=path.split(separator:",",maxSplits:1).last,let raw=Data(base64Encoded:String(encoded)){data=raw}
                else if let url=CampusContract.imageURL(path){let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=20;config.httpCookieStorage=nil;let session=URLSession(configuration:config);defer{session.invalidateAndCancel()};let (raw,response)=try await session.data(from:url);guard let http=response as? HTTPURLResponse,http.statusCode==200,raw.count<=20_000_000 else{throw APIError.invalidResponse};data=raw}
                else{throw APIError.invalidRoute}
                try Task.checkCancellation();guard current==path,let image=UIImage(data:data) else{return};photo.image=image;label.text=nil;setNeedsLayout()
            }catch is CancellationError{}catch{label.text="图片暂时无法加载，请返回后重试。"}
        }
    }
    override func layoutSubviews(){super.layoutSubviews();label.frame=bounds.insetBy(dx:20,dy:20);if lastSize != bounds.size{lastSize=bounds.size;zoomScale=1;photo.frame=CGRect(origin:.zero,size:bounds.size);contentSize=bounds.size}else if zoomScale==1{photo.frame=CGRect(origin:.zero,size:bounds.size)}}
    func viewForZooming(in scrollView:UIScrollView)->UIView?{photo}
    @objc private func toggleZoom(){setZoomScale(zoomScale>1 ? 1 : 2.5,animated:true)}
}
