#!/bin/bash

# Script to add conditional code signing settings to Xcode project

PROJECT_FILE="MoeMemos.xcodeproj/project.pbxproj"

# Add conditional code signing for main target Debug
sed -i '' 's/CODE_SIGN_IDENTITY = "Apple Development";/CODE_SIGN_IDENTITY[sdk=iphoneos*] = "Apple Development";\
				CODE_SIGN_IDENTITY[sdk=iphonesimulator*] = "";/g' "$PROJECT_FILE"

# Add conditional code signing for extensions that use CODE_SIGN_STYLE = Automatic
sed -i '' 's/CODE_SIGN_STYLE = Automatic;/CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer";\
				CODE_SIGN_IDENTITY[sdk=iphonesimulator*] = "";\
				CODE_SIGN_STYLE = Automatic;/g' "$PROJECT_FILE"

echo "Conditional code signing settings added to project file"
