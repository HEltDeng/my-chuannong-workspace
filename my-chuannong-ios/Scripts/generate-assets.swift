// Package the own Android artwork at Apple's required icon dimensions.
// Run from the iOS directory: swift Scripts/generate-assets.swift
import AppKit
import ImageIO
let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let original=root.appending(path:"Resources/my_chuannong_brand_logo.png")
guard let source=CGImageSourceCreateWithURL(original as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else{fatalError("Own product logo missing")}
let folder=root.appending(path:"Resources/Assets.xcassets/AppIcon.appiconset",directoryHint:.isDirectory)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
guard let context=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else{fatalError("Icon context unavailable")}
context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:1024,height:1024));context.interpolationQuality = .high;context.draw(image,in:CGRect(x:0,y:0,width:1024,height:1024))
guard let icon=context.makeImage(),let output=CGImageDestinationCreateWithURL(folder.appending(path:"AppIcon.png") as CFURL,"public.png" as CFString,1,nil) else{fatalError("Icon output unavailable")}
CGImageDestinationAddImage(output,icon,nil);guard CGImageDestinationFinalize(output) else{fatalError("Icon write failed")}
try Data(#"{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}"#.utf8).write(to:folder.appending(path:"Contents.json"))
try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to:folder.deletingLastPathComponent().appending(path:"Contents.json"))
print("Packaged the own product icon; original artwork preserved.")
