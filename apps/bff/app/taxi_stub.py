from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional, Dict, List
import math, time

app = FastAPI(title="Taxi Stub")

class Driver(BaseModel):
    id: str
    name: Optional[str] = None
    phone: Optional[str] = None
    vehicle_make: Optional[str] = None
    vehicle_plate: Optional[str] = None
    wallet_id: Optional[str] = None
    status: str = "offline"  # online/offline
    lat: float = 33.5138
    lon: float = 36.2765

class Ride(BaseModel):
    id: str
    rider_phone: Optional[str] = None
    rider_wallet_id: Optional[str] = None
    pickup_lat: float
    pickup_lon: float
    dropoff_lat: float
    dropoff_lon: float
    status: str = "requested"   # requested/assigned/started/completed/canceled
    driver_id: Optional[str] = None
    driver_wallet_id: Optional[str] = None
    price_cents: int = 0
    created_at: int = 0

_drivers: Dict[str, Driver] = {}
_rides: Dict[str, Ride] = {}
_seq = {"driver": 0, "ride": 0}

def _id(kind: str) -> str:
    _seq[kind] += 1
    return f"{kind[:1]}{_seq[kind]}"

def _haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    dlat = math.radians(lat2-lat1)
    dlon = math.radians(lon2-lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1))*math.cos(math.radians(lat2))*math.sin(dlon/2)**2
    c = 2*math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

@app.post("/drivers")
def register_driver(body: dict):
    did = _id("driver")
    drv = Driver(id=did,
                 name=(body.get("name") or None),
                 phone=(body.get("phone") or None),
                 vehicle_make=(body.get("vehicle_make") or None),
                 vehicle_plate=(body.get("vehicle_plate") or None),
                 wallet_id=f"taxi_wallet_{did}",
                 status="offline")
    _drivers[did] = drv
    return drv.dict()

@app.get("/drivers")
def list_drivers(status: str = "", limit: int = 50):
    arr = list(_drivers.values())
    if status in ("online","offline"):
        arr = [d for d in arr if d.status == status]
    return [d.dict() for d in arr[:max(1,min(limit,200))]]

@app.get("/drivers/{driver_id}")
def get_driver(driver_id: str):
    d = _drivers.get(driver_id)
    if not d: raise HTTPException(404, "driver not found")
    return d.dict()

@app.post("/drivers/{driver_id}/online")
def driver_online(driver_id: str):
    d = _drivers.get(driver_id)
    if not d: raise HTTPException(404, "driver not found")
    d.status = "online"
    return {"ok": True, "id": driver_id, "status": d.status}

@app.post("/drivers/{driver_id}/offline")
def driver_offline(driver_id: str):
    d = _drivers.get(driver_id)
    if not d: raise HTTPException(404, "driver not found")
    d.status = "offline"
    return {"ok": True, "id": driver_id, "status": d.status}

@app.post("/drivers/{driver_id}/wallet")
def set_driver_wallet(driver_id: str, body: dict):
    d = _drivers.get(driver_id)
    if not d: raise HTTPException(404, "driver not found")
    wid = (body.get("wallet_id") or "").strip()
    if wid:
        d.wallet_id = wid
    return d.dict()

@app.get("/drivers/{driver_id}/rides")
def driver_rides(driver_id: str, status: str = "", limit: int = 10):
    arr = [r for r in _rides.values() if r.driver_id == driver_id]
    if status:
        arr = [r for r in arr if r.status == status]
    # latest first
    arr.sort(key=lambda r: r.created_at, reverse=True)
    return [r.dict() for r in arr[:max(1,min(limit,50))]]

@app.get("/rides")
def list_rides(status: str = "", limit: int = 50):
    arr = list(_rides.values())
    if status:
        arr = [r for r in arr if r.status == status]
    arr.sort(key=lambda r: r.created_at, reverse=True)
    return [r.dict() for r in arr[:max(1,min(limit,200))]]

@app.get("/rides/{ride_id}")
def get_ride(ride_id: str):
    r = _rides.get(ride_id)
    if not r: raise HTTPException(404, "ride not found")
    return r.dict()

@app.post("/rides/quote")
def quote(body: dict):
    try:
        pLa = float(body.get("pickup_lat")); pLo = float(body.get("pickup_lon"))
        dLa = float(body.get("dropoff_lat")); dLo = float(body.get("dropoff_lon"))
    except Exception:
        raise HTTPException(400, "coords required")
    km = _haversine_km(pLa, pLo, dLa, dLo)
    base = 5000
    standard = base + int(km * 2000)
    vip = int(standard * 1.3)
    van = int(standard * 1.5)
    return {"options": [
        {"type": "VIP", "price_cents": vip},
        {"type": "VAN", "price_cents": van},
        {"type": "STANDARD", "price_cents": standard},
    ]}

@app.post("/rides/request")
def request_ride(body: dict):
    try:
        pLa = float(body.get("pickup_lat")); pLo = float(body.get("pickup_lon"))
        dLa = float(body.get("dropoff_lat")); dLo = float(body.get("dropoff_lon"))
    except Exception:
        raise HTTPException(400, "coords required")
    # pick first online driver for simplicity
    online = [d for d in _drivers.values() if d.status == "online"]
    drv = online[0] if online else None
    rid = _id("ride")
    # price same logic as quote STANDARD
    km = _haversine_km(pLa, pLo, dLa, dLo)
    price = 5000 + int(km * 2000)
    r = Ride(id=rid,
             rider_phone=(body.get("rider_phone") or None),
             rider_wallet_id=(body.get("rider_wallet_id") or None),
             pickup_lat=pLa, pickup_lon=pLo, dropoff_lat=dLa, dropoff_lon=dLo,
             status="requested", driver_id=(drv.id if drv else None),
             driver_wallet_id=(drv.wallet_id if drv else None), price_cents=price,
             created_at=int(time.time()*1000))
    _rides[rid] = r
    return r.dict()

@app.post("/rides/{ride_id}/accept")
def accept_ride(ride_id: str, driver_id: str):
    r = _rides.get(ride_id)
    if not r: raise HTTPException(404, "ride not found")
    r.status = "assigned"
    r.driver_id = driver_id
    d = _drivers.get(driver_id)
    if d: r.driver_wallet_id = d.wallet_id
    return r.dict()

@app.post("/rides/{ride_id}/start")
def start_ride(ride_id: str, driver_id: str):
    r = _rides.get(ride_id)
    if not r: raise HTTPException(404, "ride not found")
    r.status = "started"
    return r.dict()

@app.post("/rides/{ride_id}/complete")
def complete_ride(ride_id: str, driver_id: str):
    r = _rides.get(ride_id)
    if not r: raise HTTPException(404, "ride not found")
    r.status = "completed"
    return r.dict()

@app.post("/rides/{ride_id}/cancel")
def cancel_ride(ride_id: str):
    r = _rides.get(ride_id)
    if not r: raise HTTPException(404, "ride not found")
    r.status = "canceled"
    return r.dict()

