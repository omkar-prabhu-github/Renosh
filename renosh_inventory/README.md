# ReNosh Inventory Dashboard

## Overview

ReNosh Inventory is a powerful, Flutter-based dashboard application built exclusively for food establishments (restaurants, cafes, bakeries). It serves as the operational command center within the ReNosh ecosystem, allowing managers to track daily food production, monitor live sales feeds from the consumer marketplace, and intelligently manage surplus inventory. By integrating with a custom XGBoost Machine Learning backend, the app provides actionable recommendations to prevent overproduction before it happens.

## Features

- **Live Inventory Dashboard**: Real-time tracking of daily quantities of food items made, total sold, and the current surplus.
- **Smart Prep Recommendations**: Interacts with the Python ML backend to suggest ideal food preparation quantities for the next day, minimizing waste and optimizing costs.
- **Live Sales & Requests Feed**: Monitor incoming purchases from the consumer app and incoming donation requests from NGOs in real-time.
- **Surplus Management**: Easily update inventory statuses, delete obsolete items, and push surplus food to the live consumer marketplace or donation network.
- **Data Seeding & Analytics**: Built-in development tools to instantly generate 7 days of realistic historical tracking data, facilitating testing of ML insights.
- **User Authentication**: Role-restricted secure login via Firebase Authentication (ensuring only Food Establishments can access the dashboard).

## Usage

### Login
- Launch the app and log in using your establishment credentials.
- The app automatically verifies your Firebase Custom Role. If you are not registered as a "Food Establishment", access is denied.

### Dashboard & Tracking
- Use the quick "Track Food Items" form to log new dishes produced for the day.
- View real-time summary cards highlighting Production, Total Sold, and Current Surplus.
- The left panel provides a comprehensive management table to edit or delete existing food tracking records.

### Live Feeds & Operations
- On the right panel, navigate through tabs (`Live Sales`, `Requests`, `Approved`) to view real-time interactions from consumers and NGOs.
- Use the "Donate Surplus Food" dialog to bundle and post remaining items to the broader network at the end of the shift.

## Scalability

- **Cloud Integration**: Uses Firebase Firestore with snapshot listeners to ensure the dashboard reflects sales instantly without manual refreshing.
- **API-Driven Predictions**: Requests predictions via HTTP to the separate Flask/XGBoost backend, decoupling the heavy lifting from the frontend UI.
- **Modular Data Architecture**: Clearly separated collections for `food_tracking`, `purchases`, and `donations` ensure the database remains scalable and fast.

## Tech Stack

- **Frontend**: Flutter (Dart) specifically optimized for Web and Tablet views.
- **Backend**: Firebase (Authentication, Firestore).
- **ML Integration**: Connects locally to Python, Flask, and XGBoost.
- **UI Libraries**: `google_fonts`, native Flutter Material design.

## Tools

- Android Studio/Xcode/VS Code for development.
- Git for version control.
- Firebase CLI for Firebase setup.

## Prerequisites

Ensure you have the following installed/configured:

- **Flutter SDK**: Version 3.0.0 or higher.
- **Dart**: Version 2.17.0 or higher.
- **Firebase Account**: For authentication and Firestore.
- **Python Environment**: For running the companion ML server.

## Installation

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Set Up Firebase

- Ensure the Firebase project is identical to the one used for the ReNosh Consumer app.
- Update `web/index.html` with your Firebase SDK configuration if running on Web.
- Alternatively, run `flutterfire configure` to generate the `firebase_options.dart` file.

### 3. Run the ML Backend
Before starting the inventory dashboard, ensure the XGBoost prediction server is active:
```bash
cd ../xgboost-model
python server.py
```

### 4. Run the App Locally

#### For web:
```bash
flutter run -d chrome --web-port=5000
```

#### For mobile/tablet:
```bash
flutter run
```

## Security Notes

- **Role-Based Access Control**: The app actively queries the `users` collection to verify the `role == 'Food Establishment'` before granting access.
- Ensure Firebase Security Rules are properly configured so establishments can only read and write data associated with their own `establishmentId`.

## License

This project is licensed under the MIT License.

## Contact

For support or inquiries, contact project maintainers.
