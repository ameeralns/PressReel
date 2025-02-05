# PressReel

A video sharing and news application built with SwiftUI and Firebase.

## Setup

1. Clone the repository
```bash
git clone https://github.com/ameeralns/PressReel.git
cd PressReel
```

2. Firebase Setup
- Create a new Firebase project at [Firebase Console](https://console.firebase.google.com)
- Add an iOS app to your Firebase project
- Download the `GoogleService-Info.plist` file
- Copy the file to your Xcode project root (do not commit this file)
- Use the template file `GoogleService-Info.template.plist` as a reference

3. Install dependencies
```bash
# If using CocoaPods
pod install
```

## Security Note

This repository contains sensitive configuration files that should not be committed:

- `GoogleService-Info.plist`: Contains Firebase API keys and configuration
- `Config.xcconfig`: Contains OpenAI API key
- Any `.env` files: Environment variables and secrets

These files are included in `.gitignore` and should be kept secure. Use the template files as reference for setting up your local development environment.

## Features

- Video upload and sharing
- Thumbnail generation
- Video playback
- Grid layout display
- Progress tracking for uploads
- Background upload support

## Environment Setup

1. Make sure you have Xcode installed
2. Configure your Firebase credentials:
   - Copy `GoogleService-Info.sample.plist` to `GoogleService-Info.plist`
   - Replace the placeholder values with your actual Firebase configuration
3. Configure OpenAI credentials:
   - Copy `Config.template.xcconfig` to `Config.xcconfig`
   - Replace `your_openai_api_key_here` with your actual OpenAI API key
   - In Xcode, set the configuration file in your target's build settings

## Development

1. Open `PressReel.xcodeproj` in Xcode
2. Build and run the project
3. Make sure all Firebase services are properly configured in your Firebase Console

## Contributing

1. Create a new branch for your feature
2. Make your changes
3. Submit a pull request
4. Ensure no sensitive information is included in your commits 