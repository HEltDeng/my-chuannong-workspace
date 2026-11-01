#!/usr/bin/env python3
"""Install pinned official AMap SDK archives from https://lbs.amap.com/api/ios-sdk/download.
Usage: python3 Scripts/install-amap.py /path/to/downloaded/archives
"""
from pathlib import Path
import hashlib, plistlib, shutil, sys, tempfile, zipfile
ROOT=Path(__file__).resolve().parents[1]
ARCHIVES={
 'AMap_iOS_3DMap_Lib_V11.3.100.zip':'231fedcd79532932864a9b39717164cb6a3267bf53dc5d755bf9894ebba04af7',
 'AMap_iOS_Foundation_NO_IDFA_Lib_V1.9.4.zip':'e812db2c83e2542e8bcd1d6904e03d49fa1a2e20b33772e1c3f1ede14d5dd552',
 'AMap_iOS_Search_Lib_V9.8.1.zip':'d11e0b418319c74abf5228611f678b58130eac791e267d6d6e3e7ec9f41b2007',
 'AMapFoundationKit-NO-IDFA.xcprivacy.zip':'45d16718a40cc00d6845a6b8e2d98ec6793bf16df57cca75eac838dec6d15f6c',
 'AMapSearchKit.xcprivacy.zip':'abbd5a0fa0ca13c2f2b9e247b549a03a55b66e5e8cade345f797c63ab99c24c3',
 'MAMapKit.xcprivacy.zip':'8aa5fca95c086677b540686504b1ade4d1a84eebb000c9ff036c5595c584e0e0',
}
def main():
 if len(sys.argv)!=2: raise SystemExit(__doc__)
 source=Path(sys.argv[1]);destination=ROOT/'Vendor/AMap'
 for name,digest in ARCHIVES.items():
  if hashlib.sha256((source/name).read_bytes()).hexdigest()!=digest:raise SystemExit('SDK checksum mismatch: '+name)
 with tempfile.TemporaryDirectory(prefix='chuannong-amap-') as tmp:
  stage=Path(tmp)
  for name in ARCHIVES:
   with zipfile.ZipFile(source/name) as archive:
    for entry in archive.infolist():
     path=Path(entry.filename)
     if path.is_absolute() or '..' in path.parts:raise SystemExit('Invalid archive path')
     if path.parts and path.parts[0]!='__MACOSX':archive.extract(entry,stage)
  destination.mkdir(parents=True,exist_ok=True)
  for framework in stage.glob('*.framework'):shutil.copytree(framework,destination/framework.name,dirs_exist_ok=True)
  for manifest in stage.glob('*.xcprivacy'):
   name=manifest.stem.replace('-NO-IDFA','')+'Privacy';bundle=destination/(name+'.bundle');bundle.mkdir(exist_ok=True)
   shutil.copyfile(manifest,bundle/'PrivacyInfo.xcprivacy')
   (bundle/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.mychuannong.vendor.'+name,'CFBundleName':name,'CFBundlePackageType':'BNDL','CFBundleVersion':'1'}))
 print('Pinned AMap frameworks and privacy resources installed. Run update-project.py.')
if __name__=='__main__':main()
