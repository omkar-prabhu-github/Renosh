# Renosh Ecosystem: Smart Food Wastage Management Platform 🍽️🌱

*Renoshwas eloped with [Sumanth](https://github.com/sumanthd032) and [Shreesha](https://github.com/Shreesha001).*

Renosh is a comprehensive, multi-application ecosystem designed to tackle food wastage in the restaurant industry. It bridges the gap between food producers, everyday consumers, and local charities to ensure that surplus food is either sold at a discount or donated, rather than being thrown away.

---

## 📌 Project Overview

The Renosh platform consists of **three distinct Flutter applications** and **one Machine Learning backend API**, all working together seamlessly:

1. **Renosh (Main App):** The core platform featuring dual logins. **Food Establishments** can track daily food production, receive AI-powered prep recommendations, and donate surplus food. **NGOs & Charities (Acceptors)** can log in to view a live feed of donations and claim them.
2. **Renosh Inventory (`renosh_inventory`):** A dedicated, advanced dashboard strictly for Food Establishments to manage their backend inventory, seed testing data, track live sales, and post surplus food to the marketplace.
3. **Renosh Consumer (`renosh_consumer`):** A consumer-facing app (similar to Too Good To Go) where everyday users can browse discounted surplus food from nearby restaurants, add items to their cart, and checkout.
4. **XGBoost ML Backend (`xgboost-model`):** A Python Flask server that provides intelligent insights to establishments on exactly how much food to prepare tomorrow to minimize waste.

---

## 🌟 1. Renosh Main App (Dual Role)
*👉 [Learn more about the Renosh Main App](./Renosh/README.md)*

### For Food Establishments
- **Real-Time Food Tracking:** Log daily quantities of food items made, sold, and calculate surplus.
- **Smart Prep Recommendations:** Requests predictions from the ML backend to suggest ideal preparation quantities for the next day, preventing over-production.
- **One-Click Donations:** Easily move surplus food to the live "Donations" feed.
- **Sustainability Dashboard:** Track your environmental impact, total food saved, and carbon emissions reduced.

### For Acceptors (NGOs & Charities)
- **Live Donation Feed:** View a real-time list of available food donations from nearby restaurants.
- **Geolocation Filtering:** Set a search radius (e.g., 5km) to only view donations within feasible travel distance.
- **Claim & Pickup System:** One-tap claiming reserves the food and provides integrated map directions to the donor's location.

## 🌟 2. Renosh Inventory App (For Establishments)
*👉 [Learn more about Renosh Inventory](./renosh_inventory/README.md)*

- **Live Inventory Dashboard:** Advanced views for tracking production vs. sales.
- **Surplus Management:** Quickly post remaining food at the end of the day.
- **Data Seeding & Analytics:** Built-in tools to generate realistic historical tracking data to test ML insights.

## 🌟 3. Renosh Consumer App (For Everyday Users)
*👉 [Learn more about Renosh Consumer](./renosh_consumer/README.md)*

- **Discounted Food Marketplace:** Browse a live grid of high-quality surplus food from premium restaurants at lower prices.
- **Cart & Checkout System:** Add multiple servings to a cart and check out.
- **Order History:** Keep track of all past purchases and food saved.

## 🌟 4. XGBoost ML Backend
- **Custom AI Model:** Trained on over 1 million rows of synthetic restaurant data.
- **Context-Aware:** Considers the 7-day rolling surplus average, current weather, and neighborhood location to generate highly accurate unit-level predictions.
- **Flask API:** Exposes a simple REST endpoint (`/predict`) for the Flutter applications to consume.

---

## 🗂️ Project Structure

```text
MINI-PROJECT/
│
├── Renosh/                             ← Main App (Establishments & NGOs)
├── renosh_consumer/                    ← App for Everyday Consumers
├── renosh_inventory/                   ← App for Advanced Inventory Management
│
└── xgboost-model/                      ← Python ML Backend API
    ├── server.py                       
    ├── trained_model.joblib            
    └── my_restaurant_advisor.py        
```

---

## 🛠️ Tech Stack

**Frontend Apps:**
- Flutter (Web & Mobile capabilities)
- Dart
- Google Fonts & Icons

**Database & Authentication:**
- Firebase Authentication
- Cloud Firestore (NoSQL Real-time Database linking all 3 apps together)

**AI Backend:**
- Python & Flask
- Scikit-learn & XGBoost

---

## 🚀 How to Run Locally

### 1. Start the Python API Server
The establishments app requires the ML server to be running locally to fetch AI predictions.

```bash
cd xgboost-model
pip install flask flask-cors pandas xgboost scikit-learn joblib
python server.py
```
*The server will start on `http://127.0.0.1:5000`.*

### 2. Run the Flutter Apps
Open separate terminal windows to run the apps concurrently:

**For the Main App (Establishments & NGOs):**
```bash
cd Renosh
flutter run -d chrome --web-port=3000
```

**For the Consumer App:**
```bash
cd renosh_consumer
flutter run -d chrome --web-port=4000
```

**For the Inventory App:**
```bash
cd renosh_inventory
flutter run -d chrome --web-port=5000
```

---

## 📄 License
MIT License — free to use, modify, and distribute.
