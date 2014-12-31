#!/bin/sh
cd src/splash/
rm -rf export
echo "Building splash project..."
(lime build linux) > /dev/null
cd ../client
rm -rf export
echo "Building client project..."
(lime build linux) > /dev/null
cd ..
VER=`cat version.txt | sed -e 's,\s,_,'`
TGT=hxScout-$VER
echo "Packaging $TGT.tgz"
cp splash/export/linux64/cpp/bin/hxScoutSplash client/export/linux64/cpp/bin/
mkdir $TGT
cp -rf client/export/linux64/cpp/bin/* $TGT/
tar -czf ../$TGT.tgz $TGT
rm -rf $TGT splash/export client/export
