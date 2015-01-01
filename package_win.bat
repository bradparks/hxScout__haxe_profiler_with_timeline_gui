@echo off
cd src\splash
rmdir /s /q export

echo Building splash project...
call lime build windows > NUL
cd ..\client

rmdir /s /q export
echo Building client project...
call lime build windows > NUL

cd ..
set /p VER=<version.txt
set TGT=hxScout-%VER: =_%
echo Packaging %TGT%-win.zip
copy splash\export\windows\cpp\bin\hxScoutSplash.exe client\export\windows\cpp\bin\ > NUL
cd client\export\windows\cpp\
ren bin %TGT%
..\..\..\..\..\util\zip.exe -r %TGT%-win.zip %TGT% > NUL
move %TGT%-win.zip ..\..\..\..\..\ > NUL
cd ..\..\..\..\..\
