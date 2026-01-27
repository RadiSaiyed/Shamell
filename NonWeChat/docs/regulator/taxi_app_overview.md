# Shamell Taxi App – Technical Overview for Regulatory Security Review

## 1. Architecture

- **Client (Android app)**  
  - Flutter app (`clients/shamell_flutter`) with taxi modules: Rider, Driver, Operator (Ops‑Admin is a separate Flutter app).  
  - All communication is over HTTPS to the SuperApp BFF (backend‑for‑frontend).

- **Backend**  
  - **SuperApp BFF** (`apps/bff/app/main.py`, FastAPI, Python):  
    - Session and OTP login endpoints (`/auth/request_code`, `/auth/verify`).  
    - Proxies to microservices (including Taxi, Bus and other domains).  
  - **Taxi Service** (`apps/taxi/app/main.py`, FastAPI, Python):  
    - Manages drivers, rides and pricing.  
    - Sends FCM push notifications to drivers for newly assigned rides.

## 2. Authentication & OTP

- Login is based on phone number + one‑time code (OTP).  
- Endpoints:
  - `POST /auth/request_code` – generates an OTP, stores it temporarily in the BFF process, and (in this demo build) returns the OTP in the JSON response.  
  - `POST /auth/verify` – validates OTP, creates a session (`sa_session` cookie) and, if needed, creates wallet and Taxi‑Rider records.
- **Regulatory note**:  
  - The “Demo OTP” (code shown directly in the app) is meant for staging/test only and is clearly marked in the UI.  
  - In production deployments, OTP delivery would be via SMS or another out‑of‑band channel instead of being shown in the app.

## 3. Roles

- **Rider (passenger)**  
  - Screen: `TaxiRiderPage` (`clients/shamell_flutter/lib/core/taxi/taxi_rider.dart`).  
  - Main functions: book a ride, see ride status, cancel a ride (cancellation fee 4000 SYP, paid in cash to the driver), view ride history.

- **Driver**  
  - Screen: `TaxiDriverPage` (`clients/shamell_flutter/lib/core/taxi/taxi_driver.dart`).  
  - Main functions: go online/offline, accept/deny rides, start/complete rides, call the rider, open navigation to pickup/dropoff.  
  - Receives FCM push notifications when new rides are assigned.

- **Operator (dispatcher / admin view)**  
  - Separate Flutter app: Ops Admin (`clients/ops_admin_flutter`).  
  - TaxiOperatorPage (`lib/taxi_operator.dart`): manage drivers (create/block/unblock), adjust balances, list rides and complaints.  
  - Login also via OTP against the same BFF.

## 4. External Services & Libraries

- **Google / Firebase**  
  - Firebase Cloud Messaging (FCM) for push notifications to drivers:  
    - Client: `firebase_core`, `firebase_messaging`.  
    - Backend: `apps/taxi/app/fcm.py` uses a service account and the FCM HTTP v1 API.  
  - Google Maps: `google_maps_flutter` + `GMAPS_API_KEY` (used only for map display and routing).

- **Other Flutter packages** (selection, no server‑side business logic):  
  - `geolocator` / `geocoding` – GPS position and geocoding.  
  - `flutter_local_notifications` – local notifications (e.g. “Fare credited”).  
  - `shared_preferences` – local settings (e.g. base URL, last phone number).

## 5. Data processed by the app

- **Personal data**  
  - User phone number (Rider/Driver/Operator).  
  - Location data (pickup and dropoff coordinates).  
  - Ride history (e.g. ride status, approximate fare).

> **Important for this build:** All rides in the Shamell taxi app are paid **in cash only**. No digital payments are performed by this version of the app.

## 6. Permissions (Android)

- `INTERNET` – network communication with the backend.  
- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` – precise/approximate location for pickup/dropoff.  
- `CAMERA` – QR scanning in other modules (not critical for core taxi flow).  
- `READ_CONTACTS` – optional for convenience features in other modules (not taxi‑specific).  
- `POST_NOTIFICATIONS` – shows notifications (e.g. for new rides, fare credited).

## 7. Security & Configuration

- **Secrets / keys**  
  - The FCM service‑account JSON is used only on the backend (`FCM_SERVICE_ACCOUNT_FILE`); it is not bundled into the client app.  
  - Client‑side keys (e.g. the Google Maps API key in `AndroidManifest`) are standard restricted API keys.

- **Configuration**  
  - The BFF base URL is configurable in the apps (`BASE_URL` and a stored `base_url` preference).  
  - Staging vs. production environments differ only in URLs and backend secrets, not in client binaries.

## 8. Artefacts provided to the regulator

- On the removable drive:
  - APK: `Shamell.apk` (copied from `clients/shamell_flutter/build/app/outputs/flutter-apk/app-release.apk`).  
  - This document: `docs/taxi_app_overview.md`.  
  - Build instructions: `docs/build_instructions_android.md`.  
  - Logo assets: `logo/shamell_steering.png` and `logo/shamell_steering.svg`.

## 10.1 Ride Request Workflow

1. **Passenger location initialization**  
   The passenger specifies their current location using GPS or via manual selection within the mobile application.

2. **Destination entry and fare estimation**  
   The passenger enters the destination.  
   The application computes and displays an estimated fare based on the expected distance and travel time (via `/rides/quote` in the Taxi Service).

3. **Ride request submission**  
   Upon selecting “Request Ride”, the client application sends a ride request payload to the BFF (Backend‑for‑Frontend) service. The payload includes:
   - Pickup coordinates  
   - Drop‑off coordinates  
   - Passenger identifier

4. **Dispatch via Taxi Service**  
   The BFF forwards the request to the Taxi Service, which is responsible for driver matching and dispatch operations.

5. **Driver matching**  
   The Taxi Service selects the nearest available driver using an internal matching algorithm that considers:
   - Geographical proximity  
   - Driver availability status (Online / Offline)  
   - Recency of last completed trip

6. **Driver notification**  
   Upon selecting a suitable driver, the Taxi Service triggers an FCM push notification to the driver device, for example:  
   “A new ride request is awaiting your acceptance.”

7. **Driver acceptance**  
   If the driver accepts the request:  
   - The system generates a ride confirmation event and sets the ride status to “accepted”.  
   - The passenger receives a notification indicating that the driver is en route.

8. **Trip completion**  
   Upon arrival at the destination, the driver selects “End Ride” in the application. The system then:
   1. Calculates the final fare (distance + time based tariff).  
   2. Records the trip details in both driver and passenger trip histories.  
   3. Processes payment — in this build via **cash** from passenger to driver.

9. **Wallet settlement logic (Driver → SuperAdmin)**  
   After the fare is finalized, the system performs an automatic wallet‑settlement operation on the internal balances:
   - 10 % of the fare amount is deducted from the driver’s wallet balance (platform commission; configurable via `TAXI_BROKERAGE_RATE`, default 0.10).  
   - This amount is allocated to the SuperAdmin wallet as the platform commission.

   **Example:**  
   If the final fare is 10 USD, then:
   - 1.00 USD is transferred to the SuperAdmin wallet (commission).  
   - 9.00 USD remains with the driver (cash collected from passenger).
