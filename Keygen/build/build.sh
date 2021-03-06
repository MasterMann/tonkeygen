set -e
FullExecPath=$PWD
pushd `dirname $0` > /dev/null
FullScriptPath=`pwd`
popd > /dev/null

Error () {
  cd $FullExecPath
  echo "$1"
  exit 1
}

if [ ! -f "$FullScriptPath/target" ]; then
  Error "Build target not found!"
fi

while IFS='' read -r line || [[ -n "$line" ]]; do
  BuildTarget="$line"
done < "$FullScriptPath/target"

while IFS='' read -r line || [[ -n "$line" ]]; do
  set $line
  eval $1="$2"
done < "$FullScriptPath/version"

AppVersionStrFull="$AppVersionStr"

echo ""
HomePath="$FullScriptPath/.."
if [ "$BuildTarget" == "linux" ]; then
  echo "Building version $AppVersionStrFull for Linux 64bit.."
  SetupFile="tonkeygen.$AppVersionStrFull.linux.tar.xz"
  ProjectPath="$HomePath/../out"
  ReleasePath="$ProjectPath/Release"
  BinaryName="Keygen"
elif [ "$BuildTarget" == "linux32" ]; then
  echo "Building version $AppVersionStrFull for Linux 32bit.."
  SetupFile="tonkeygen.$AppVersionStrFull.linux32.tar.xz"
  ProjectPath="$HomePath/../out"
  ReleasePath="$ProjectPath/Release"
  BinaryName="Keygen"
elif [ "$BuildTarget" == "mac" ]; then
  echo "Building version $AppVersionStrFull for OS X 10.8+.."
  if [ "$AC_USERNAME" == "" ]; then
    Error "AC_USERNAME not found!"
  fi
  SetupFile="tonkeygen.$AppVersionStrFull.mac.dmg"
  ProjectPath="$HomePath/../out"
  ReleasePath="$ProjectPath/Release"
  BinaryName="Keygen"
else
  Error "Invalid target!"
fi

if [ -d "$ReleasePath/deploy/$AppVersionStrMajor/$AppVersionStr" ]; then
  Error "Deploy folder for version $AppVersionStr already exists!"
fi

DeployPath="$ReleasePath/deploy/$AppVersionStrMajor/$AppVersionStrFull"

if [ "$BuildTarget" == "linux" ] || [ "$BuildTarget" == "linux32" ]; then
  BackupPath="/media/psf/backup/tonkeygen/$AppVersionStrMajor/$AppVersionStrFull/t$BuildTarget"
  if [ ! -d "/media/psf/backup" ]; then
    Error "Backup folder not found!"
  fi

  ./configure.sh

  cd $ProjectPath
  cmake --build . --config Release --target Keygen -- -j8
  cd $ReleasePath

  if [ ! -f "$ReleasePath/$BinaryName" ]; then
    Error "$BinaryName not found!"
  fi

  # BadCount=`objdump -T $ReleasePath/$BinaryName | grep GLIBC_2\.1[6-9] | wc -l`
  # if [ "$BadCount" != "0" ]; then
  #   Error "Bad GLIBC usages found: $BadCount"
  # fi

  # BadCount=`objdump -T $ReleasePath/$BinaryName | grep GLIBC_2\.2[0-9] | wc -l`
  # if [ "$BadCount" != "0" ]; then
  #   Error "Bad GLIBC usages found: $BadCount"
  # fi

  # BadCount=`objdump -T $ReleasePath/$BinaryName | grep GCC_4\.[3-9] | wc -l`
  # if [ "$BadCount" != "0" ]; then
  #   Error "Bad GCC usages found: $BadCount"
  # fi

  # BadCount=`objdump -T $ReleasePath/$BinaryName | grep GCC_[5-9]\. | wc -l`
  # if [ "$BadCount" != "0" ]; then
  #   Error "Bad GCC usages found: $BadCount"
  # fi

  echo "Stripping the executable.."
  strip -s "$ReleasePath/$BinaryName"
  echo "Done!"

  echo "Removing RPATH.."
  chrpath -d "$ReleasePath/$BinaryName"
  echo "Done!"

  if [ ! -d "$ReleasePath/deploy" ]; then
    mkdir "$ReleasePath/deploy"
  fi

  if [ ! -d "$ReleasePath/deploy/$AppVersionStrMajor" ]; then
    mkdir "$ReleasePath/deploy/$AppVersionStrMajor"
  fi

  echo "Copying $BinaryName to deploy/$AppVersionStrMajor/$AppVersionStrFull..";
  mkdir "$DeployPath"
  mkdir "$DeployPath/$BinaryName"
  mv "$ReleasePath/$BinaryName" "$DeployPath/$BinaryName/"
  cd "$DeployPath"
  tar -cJvf "$SetupFile" "$BinaryName/"

  mkdir -p $BackupPath
  cp "$SetupFile" "$BackupPath/"
fi

if [ "$BuildTarget" == "mac" ]; then
  BackupPath="$HomePath/../../../Projects/backup/tonkeygen/$AppVersionStrMajor/$AppVersionStrFull"
  if [ ! -d "$HomePath/../../../Projects/backup" ]; then
    Error "Backup path not found!"
  fi

  ./configure.sh

  cd $ProjectPath
  cmake --build . --config Release --target Keygen
  cd $ReleasePath

  if [ ! -d "$ReleasePath/$BinaryName.app" ]; then
    Error "$BinaryName.app not found!"
  fi

  if [ ! -d "$ReleasePath/$BinaryName.app.dSYM" ]; then
    Error "$BinaryName.app.dSYM not found!"
  fi

  echo "Stripping the executable.."
  strip "$ReleasePath/$BinaryName.app/Contents/MacOS/$BinaryName"
  echo "Done!"

  echo "Signing the application.."
  codesign --force --deep --timestamp --options runtime --sign "Developer ID Application: John Preston" "$ReleasePath/$BinaryName.app" --entitlements "$HomePath/Resources/mac/Keygen.entitlements"
  echo "Done!"

  AppUUID=`dwarfdump -u "$ReleasePath/$BinaryName.app/Contents/MacOS/$BinaryName" | awk -F " " '{print $2}'`
  DsymUUID=`dwarfdump -u "$ReleasePath/$BinaryName.app.dSYM" | awk -F " " '{print $2}'`
  if [ "$AppUUID" != "$DsymUUID" ]; then
    Error "UUID of binary '$AppUUID' and dSYM '$DsymUUID' differ!"
  fi

  if [ ! -f "$ReleasePath/$BinaryName.app/Contents/Resources/Icon.icns" ]; then
    Error "Icon.icns not found in Resources!"
  fi

  if [ ! -f "$ReleasePath/$BinaryName.app/Contents/MacOS/$BinaryName" ]; then
    Error "$BinaryName not found in MacOS!"
  fi

  if [ ! -d "$ReleasePath/$BinaryName.app/Contents/_CodeSignature" ]; then
    Error "$BinaryName signature not found!"
  fi

  cd "$ReleasePath"

  cp -f tsetup_template.dmg tsetup.temp.dmg
  TempDiskPath=`hdiutil attach -nobrowse -noautoopenrw -readwrite tsetup.temp.dmg | awk -F "\t" 'END {print $3}'`
  cp -R "./$BinaryName.app" "$TempDiskPath/"
  bless --folder "$TempDiskPath/" --openfolder "$TempDiskPath/"
  hdiutil detach "$TempDiskPath"
  hdiutil convert tsetup.temp.dmg -format UDZO -imagekey zlib-level=9 -ov -o "$SetupFile"
  rm tsetup.temp.dmg

  echo "Beginning notarization process."
  set +e
  xcrun altool --notarize-app --primary-bundle-id "org.ton.TonKeyGenerator" --username "$AC_USERNAME" --password "@keychain:AC_PASSWORD" --file "$SetupFile" > request_uuid.txt
  set -e
  while IFS='' read -r line || [[ -n "$line" ]]; do
    Prefix=$(echo $line | cut -d' ' -f 1)
    Value=$(echo $line | cut -d' ' -f 3)
    if [ "$Prefix" == "RequestUUID" ]; then
      RequestUUID=$Value
    fi
  done < "request_uuid.txt"
  if [ "$RequestUUID" == "" ]; then
    cat request_uuid.txt
    Error "Could not extract Request UUID."
  fi
  echo "Request UUID: $RequestUUID"
  rm request_uuid.txt

  RequestStatus=
  LogFile=
  while [[ "$RequestStatus" == "" ]]; do
    sleep 5
    xcrun altool --notarization-info "$RequestUUID" --username "$AC_USERNAME" --password "@keychain:AC_PASSWORD" > request_result.txt
    while IFS='' read -r line || [[ -n "$line" ]]; do
      Prefix=$(echo $line | cut -d' ' -f 1)
      Value=$(echo $line | cut -d' ' -f 2)
      if [ "$Prefix" == "LogFileURL:" ]; then
        LogFile=$Value
      fi
      if [ "$Prefix" == "Status:" ]; then
        if [ "$Value" == "in" ]; then
          echo "In progress..."
        else
          RequestStatus=$Value
          echo "Status: $RequestStatus"
        fi
      fi
    done < "request_result.txt"
  done
  if [ "$RequestStatus" != "success" ]; then
    echo "Notarization problems, response:"
    cat request_result.txt
    if [ "$LogFile" != "" ]; then
      echo "Requesting log..."
      curl $LogFile
    fi
    Error "Notarization FAILED."
  fi
  rm request_result.txt

  if [ "$LogFile" != "" ]; then
    echo "Requesting log..."
    curl $LogFile > request_log.txt
  fi

  xcrun stapler staple "$ReleasePath/$BinaryName.app"
  xcrun stapler staple "$ReleasePath/$SetupFile"

  if [ ! -d "$ReleasePath/deploy" ]; then
    mkdir "$ReleasePath/deploy"
  fi

  if [ ! -d "$ReleasePath/deploy/$AppVersionStrMajor" ]; then
    mkdir "$ReleasePath/deploy/$AppVersionStrMajor"
  fi

  if [ "$BuildTarget" == "mac" ]; then
    echo "Copying $BinaryName.app to deploy/$AppVersionStrMajor/$AppVersionStr..";
    mkdir "$DeployPath"
    mkdir "$DeployPath/$BinaryName"
    cp -r "$ReleasePath/$BinaryName.app" "$DeployPath/$BinaryName/"
    mv "$ReleasePath/$BinaryName.app.dSYM" "$DeployPath/"
    rm "$ReleasePath/$BinaryName.app/Contents/MacOS/$BinaryName"
    rm "$ReleasePath/$BinaryName.app/Contents/Info.plist"
    rm -rf "$ReleasePath/$BinaryName.app/Contents/_CodeSignature"
    mv "$ReleasePath/$SetupFile" "$DeployPath/"

    mkdir -p "$BackupPath/tmac"
    cp "$DeployPath/$SetupFile" "$BackupPath/tmac/"
  fi
fi

echo "Version $AppVersionStrFull is ready!";
echo -en "\007";
sleep 1;
echo -en "\007";
sleep 1;
echo -en "\007";

if [ "$BuildTarget" == "mac" ]; then
  if [ -f "$ReleasePath/request_log.txt" ]; then
    DisplayingLog=
    while IFS='' read -r line || [[ -n "$line" ]]; do
      if [ "$DisplayingLog" == "1" ]; then
        echo $line
      else
        Prefix=$(echo $line | cut -d' ' -f 1)
        Value=$(echo $line | cut -d' ' -f 2)
        if [ "$Prefix" == '"issues":' ]; then
          if [ "$Value" != "null" ]; then
            echo "NB! Notarization log issues:"
            echo $line
            DisplayingLog=1
          else
            DisplayingLog=0
          fi
        fi
      fi
    done < "$ReleasePath/request_log.txt"
    if [ "$DisplayingLog" != "0" ] && [ "$DisplayingLog" != "1" ]; then
      echo "NB! Notarization issues not found:"
      cat "$ReleasePath/request_log.txt"
    else
      rm "$ReleasePath/request_log.txt"
    fi
  else
    echo "NB! Notarization log not found :("
  fi
fi
