#!/usr/bin/env python3
"""Reproducible app + WidgetKit project. Does not build, run, sign, or execute tests."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
objects = {}

def ident(name):
    return hashlib.sha256(('mychuannong-ios:' + name).encode()).hexdigest()[:24].upper()

def add(object_name, isa, fixed=None, **fields):
    key = fixed or ident(object_name)
    objects[key] = {'isa': isa, **fields}
    return key

def file(path, kind):
    return add('file:' + path, 'PBXFileReference', path=path, lastKnownFileType=kind, sourceTree='<group>')

def build(path, reference, target='app', **fields):
    return add('build:' + target + ':' + path, 'PBXBuildFile', fileRef=reference, **fields)

def phase(object_name, kind, files, **fields):
    return add(object_name, kind, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0, **fields)

app_sources=[]; core_sources=[]; app_files=[]; core_files=[]
for folder, files, builds in [('App',app_files,app_sources),('Core/Sources/ChuannongCore',core_files,core_sources)]:
    for source in sorted((root/folder).glob('*.swift')):
        path=str(source.relative_to(root)); ref=file(path,'sourcecode.swift');files.append(ref);builds.append(build(path,ref))
widget_sources=[];widget_files=[]
for path in ['Widget/SchoolWidgets.swift','Core/Sources/ChuannongCore/WidgetModels.swift']:
    ref=file(path,'sourcecode.swift')
    if path.startswith('Widget/'):widget_files.append(ref)
    widget_sources.append(build(path,ref,'widget'))
resource_files=[];resource_builds=[]
for resource in sorted((root/'Resources').rglob('*')):
    if not resource.is_file() or resource.name.startswith('.'):continue
    if '.xcassets' in str(resource):continue
    path=str(resource.relative_to(root));kind={'.xcprivacy':'text.plist.xml','.json':'text.json','.jpg':'image.jpeg','.jpeg':'image.jpeg','.png':'image.png','.webp':'image.webp'}.get(resource.suffix,'file')
    ref=file(path,kind);resource_files.append(ref);resource_builds.append(build(path,ref))
for resource in sorted((root/'Resources').glob('*.xcassets')):
    path=str(resource.relative_to(root));ref=file(path,'folder.assetcatalog');resource_files.append(ref);resource_builds.append(build(path,ref))
# These official SDKs are static frameworks, so link on device and copy their resource bundles.
# Vendor's distribution has device arm64 + Intel simulator; it has no arm64 simulator slice.
vendor_files=[]
for name in ['AMapFoundationKit','AMapSearchKit','MAMapKit']:
    path='Vendor/AMap/'+name+'.framework';vendor_files.append(file(path,'wrapper.framework'))
    for resource in sorted((root/path).glob('*.bundle')):
        relative=str(resource.relative_to(root));ref=file(relative,'wrapper.plug-in');vendor_files.append(ref);resource_builds.append(build(relative,ref))
for resource in sorted((root/'Vendor/AMap').glob('*Privacy.bundle')):
    relative=str(resource.relative_to(root));ref=file(relative,'wrapper.plug-in');vendor_files.append(ref);resource_builds.append(build(relative,ref))
configuration_files=[file('Config/App.xcconfig','text.xcconfig'),file('Config/Release.xcconfig','text.xcconfig'),file('Config/Local.xcconfig.example','text'),file('Config/Release.local.xcconfig.example','text'),file('Configuration/Info.plist','text.plist.xml'),file('Configuration/App.entitlements','text.plist.entitlements'),file('Configuration/Widget.entitlements','text.plist.entitlements'),file('Widget/Info.plist','text.plist.xml')]
base=configuration_files[0]
release_base=configuration_files[1]
app_product=add('app-product','PBXFileReference',fixed='100000000000000000000007',explicitFileType='wrapper.application',includeInIndex=0,path='MyChuannong.app',sourceTree='BUILT_PRODUCTS_DIR')
widget_product=add('widget-product','PBXFileReference',explicitFileType='wrapper.app-extension',includeInIndex=0,path='SchoolWidgets.appex',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products','PBXGroup',children=[app_product,widget_product],name='Products',sourceTree='<group>')
groups=[]
for name,children in [('App',app_files),('ChuannongCore',core_files),('Widget',widget_files),('Resources',resource_files),('Configuration',configuration_files),('Vendor',vendor_files)]:
    groups.append(add('group:'+name,'PBXGroup',children=children,name=name,sourceTree='<group>'))
main=add('main','PBXGroup',children=groups+[products],sourceTree='<group>')
project_id='100000000000000000000001';app_id='100000000000000000000006';widget_id=ident('widget-target')
common={'CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','ENABLE_USER_SCRIPT_SANDBOXING':'YES','ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS':'YES'}
configs=[]
for name in ['Debug','Release']:
    values={**common,'DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym'}
    if name=='Debug':values.update(ENABLE_TESTABILITY='YES',ENABLE_PREVIEWS='YES',ONLY_ACTIVE_ARCH='YES',GCC_OPTIMIZATION_LEVEL='0',SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG $(inherited)',SWIFT_OPTIMIZATION_LEVEL='-Onone')
    else:values.update(SWIFT_COMPILATION_MODE='wholemodule',SWIFT_OPTIMIZATION_LEVEL='-O')
    configs.append(add('project-config:'+name,'XCBuildConfiguration',buildSettings=values,name=name,baseConfigurationReference=base if name=='Debug' else release_base))
project_configs=add('project-configs','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')

def target_configs(target):
    builds=[]
    for name in ['Debug','Release']:
        bundle='com.mychuannong.app' if name=='Release' else 'com.mychuannong.app.development'
        values={'CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1.0','GENERATE_INFOPLIST_FILE':'YES','PRODUCT_NAME':'$(TARGET_NAME)','TARGETED_DEVICE_FAMILY':'1,2','SWIFT_EMIT_LOC_STRINGS':'YES'}
        if target=='app':
            values.update(PRODUCT_BUNDLE_IDENTIFIER=bundle,PRODUCT_NAME='MyChuannong' if name=='Release' else 'MyChuannongDevelopment',INFOPLIST_FILE='Configuration/Info.plist',CODE_SIGN_ENTITLEMENTS='Configuration/App.entitlements',INFOPLIST_KEY_CFBundleDisplayName='我的川农' if name=='Release' else '我的川农开发',INFOPLIST_KEY_UIApplicationSceneManifest_Generation='YES',INFOPLIST_KEY_UILaunchScreen_Generation='YES',INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone='UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad='UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight')
            values['ASSETCATALOG_COMPILER_APPICON_NAME']='AppIcon'
            values['FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]']='$(inherited) $(PROJECT_DIR)/Vendor/AMap'
            values['OTHER_LDFLAGS[sdk=iphoneos*]']='$(inherited) -ObjC -lz -lc++ -lsqlite3 -framework AMapFoundationKit -framework AMapSearchKit -framework MAMapKit -framework CoreLocation -framework CoreTelephony -framework SystemConfiguration -framework Security -framework Metal -framework OpenGLES -framework GLKit -framework Accelerate -framework CFNetwork'
        else:
            values.update(PRODUCT_BUNDLE_IDENTIFIER=bundle+'.widgets',INFOPLIST_FILE='Widget/Info.plist',CODE_SIGN_ENTITLEMENTS='Configuration/Widget.entitlements',INFOPLIST_KEY_CFBundleDisplayName='我的川农课表',SKIP_INSTALL='YES',APPLICATION_EXTENSION_API_ONLY='YES')
        builds.append(add(target+'-config:'+name,'XCBuildConfiguration',name=name,buildSettings=values))
    return add(target+'-configs','XCConfigurationList',buildConfigurations=builds,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
widget_phases=[phase('widget-sources','PBXSourcesBuildPhase',widget_sources),phase('widget-frameworks','PBXFrameworksBuildPhase',[]),phase('widget-resources','PBXResourcesBuildPhase',[])]
add('widget-target','PBXNativeTarget',fixed=widget_id,buildConfigurationList=target_configs('widget'),buildPhases=widget_phases,buildRules=[],dependencies=[],name='SchoolWidgets',productName='SchoolWidgets',productReference=widget_product,productType='com.apple.product-type.app-extension')
proxy=add('widget-proxy','PBXContainerItemProxy',containerPortal=project_id,proxyType=1,remoteGlobalIDString=widget_id,remoteInfo='SchoolWidgets')
dependency=add('widget-dependency','PBXTargetDependency',target=widget_id,targetProxy=proxy)
embed=build('SchoolWidgets.appex',widget_product,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
app_phases=[phase('app-sources','PBXSourcesBuildPhase',app_sources+core_sources),phase('app-frameworks','PBXFrameworksBuildPhase',[]),phase('app-resources','PBXResourcesBuildPhase',resource_builds),phase('embed-widget','PBXCopyFilesBuildPhase',[embed],dstPath='',dstSubfolderSpec=13,name='Embed App Extensions')]
add('app-target','PBXNativeTarget',fixed=app_id,buildConfigurationList=target_configs('app'),buildPhases=app_phases,buildRules=[],dependencies=[dependency],name='MyChuannongDevelopment',productName='MyChuannongDevelopment',productReference=app_product,productType='com.apple.product-type.application')
add('project','PBXProject',fixed=project_id,attributes={'BuildIndependentTargetsInParallel':'YES','LastSwiftUpdateCheck':'2660','LastUpgradeCheck':'2660','TargetAttributes':{app_id:{'SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':1}}},widget_id:{'SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':1}}}}},buildConfigurationList=project_configs,compatibilityVersion='Xcode 16.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['zh-Hans','en','Base'],mainGroup=main,preferredProjectObjectVersion=77,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app_id,widget_id])

def encode(value,depth=0):
    if isinstance(value,dict):return '{\n'+''.join('  '*(depth+1)+json.dumps(k,ensure_ascii=False)+' = '+encode(v,depth+1)+';\n' for k,v in value.items())+'  '*depth+'}'
    if isinstance(value,list):return '('+', '.join(encode(v,depth) for v in value)+')'
    if isinstance(value,int):return str(value)
    return json.dumps(value,ensure_ascii=False)

project={'archiveVersion':1,'classes':{},'objectVersion':77,'objects':objects,'rootObject':project_id}
(root/'MyChuannong.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(project)+'\n')
print('Updated app and widget source membership; no build or tests run.')
