# ReNosh Consumer App

## Overview

ReNosh Consumer is a Flutter-based application that empowers everyday users to fight food wastage by purchasing high-quality surplus food from local restaurants at discounted prices. Operating similarly to a "Too Good To Go" model, it connects directly to the ReNosh backend ecosystem. The app features a live marketplace, a real-time cart system, and seamless integration with Firebase for secure authentication and instant database updates.

## Features

- **Live Marketplace**: Browse a constantly updated grid of surplus food available from nearby premium establishments.
- **Cart & Checkout System**: Easily select quantities, add items to a local cart, and execute batch checkout transactions.
- **Real-Time Sync**: Every purchase instantly updates the restaurant's inventory database, ensuring stock levels are always accurate.
- **Offline Support**: Access cached data when offline, ensuring a smooth user experience even with poor connectivity.
- **User Authentication**: Secure login flow for everyday consumers using Firebase Authentication.
- **Responsive Design**: Smooth animations (powered by `flutter_animate`) and a modern, dark-themed UI using Google Fonts.

## Usage

### Login
- Launch the app and log in using your consumer credentials via Firebase Authentication.
- If no user is logged in, you’ll be redirected to the secure login screen.

### Browse Items
- View a personalized marketplace displaying dishes with their remaining surplus servings.
- Tap the `+` or `-` buttons on any item to select the desired quantity.

### Cart & Checkout
- Tap the "Add to Cart" button to stage items. A cart counter will appear at the top of the screen.
- Open the cart to review your selections and tap "Checkout Now" to process the order.
- The transaction uses a Firestore batch write to guarantee that the purchase and the restaurant's inventory deduction happen simultaneously.

## Scalability

- **Cloud Integration**: Uses Firebase Firestore for real-time data storage and batch processing, enabling seamless scaling during high-traffic hours.
- **Modular Design**: The app’s component-driven architecture allows for easy addition of new features like payment gateways or geolocation maps.
- **Efficient State Management**: Uses local memory caching for the cart to reduce unnecessary database reads.

## Tech Stack

- **Frontend**: Flutter (Dart) for cross-platform mobile and web development.
- **Backend**: Firebase (Authentication, Firestore) for user management, real-time tracking, and purchase history logging.
- **UI Libraries**: `google_fonts`, `flutter_animate`.

## Tools

- Android Studio/Xcode/VS Code for development.
- Git for version control.
- Firebase CLI for Firebase setup.

## Prerequisites

Ensure you have the following installed/configured:

- **Flutter SDK**: Version 3.0.0 or higher.
- **Dart**: Version 2.17.0 or higher.
- **Firebase Account**: For authentication and Firestore configuration.
- **Android Studio/Xcode**: For running the app locally.

## Installation

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Set Up Firebase

- Create a Firebase project in the Firebase Console (make sure it links to the same project as the main Renosh app).
- Add Android, iOS, and web apps to your Firebase project.

#### For Mobile (Android/iOS):
- Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) from Firebase Console.
- Place them in `android/app/` and `ios/Runner/`, respectively.

#### Firebase CLI Setup
```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
flutterfire configure
```

#### For Web:
- Copy the Firebase configuration from Firebase Console.
- Ensure `web/index.html` is updated with the Firebase SDK and configuration block.

### 3. Run the App Locally

#### For web:
```bash
flutter run -d chrome --web-port=4000
```

#### For mobile:
```bash
flutter run
```

## Security Notes

- Sensitive files are excluded via `.gitignore`.
- Purchases are executed securely via Firestore Batch Commits to prevent race conditions.
- Regularly review Firebase Security Rules to ensure consumers can only read available items and write to their own purchase history.

## License

This project is licensed under the MIT License.

## Contact

For support or inquiries, contact project maintainers.
