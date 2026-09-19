# ===============================================
# SMART ROAD DAMAGE DETECTION & MANAGEMENT SYSTEM
# ===============================================

import requests
import urllib.parse
import streamlit as st
from ultralytics import YOLO
import tempfile
import os
import cv2
import pandas as pd
from datetime import datetime
import folium
from streamlit_folium import st_folium
import matplotlib.pyplot as plt
from folium.plugins import HeatMap

# ===============================================
# PAGE CONFIG
# ===============================================

st.set_page_config(page_title="AI Road Damage Management", layout="wide")

st.title("🛣 AI Road Damage Detection & Monitoring System")
st.caption("Detection • Mapping • Alerts • Infrastructure Analytics")

# ===============================================
# LOAD MODEL
# ===============================================

@st.cache_resource
def load_model():
    return YOLO("best.pt")

model = load_model()

# ===============================================
# SESSION STATE
# ===============================================

if "df" not in st.session_state:
    st.session_state.df = None

if "img" not in st.session_state:
    st.session_state.img = None

# ===============================================
# LOCATION
# ===============================================

def get_location():
    try:
        response = requests.get("https://ipinfo.io/json").json()
        loc = response.get("loc")
        city = response.get("city")
        region = response.get("region")
        country = response.get("country")

        lat, lon = loc.split(",")
        return float(lat), float(lon), f"{city}, {region}, {country}"
    except:
        return -1.0, 36.0, "Unknown Location"

lat, lon, location_name = get_location()

# ===============================================
# STREET NAME
# ===============================================

def get_street_name(lat, lon):
    try:
        url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lon}&format=json"
        headers = {"User-Agent": "road-damage-system"}
        data = requests.get(url, headers=headers).json()

        address = data.get("address", {})
        road = address.get("road", "Unknown Road")
        suburb = address.get("suburb", "")
        city = address.get("city", "")

        return f"{road}, {suburb}, {city}"
    except:
        return "Unknown Street"

street_name = get_street_name(lat, lon)

# ===============================================
# SIDEBAR
# ===============================================

st.sidebar.header("⚙ Settings")

confidence = st.sidebar.slider("Confidence", 0.1, 0.9, 0.3, 0.05)
enable_camera = st.sidebar.toggle("Enable Camera")

st.sidebar.write("Latitude:", lat)
st.sidebar.write("Longitude:", lon)
st.sidebar.write("Street:", street_name)

# ===============================================
# SEVERITY
# ===============================================

def severity(area):
    if area < 5000:
        return "Low"
    elif area < 20000:
        return "Medium"
    return "High"

# ===============================================
# WHATSAPP ALERT
# ===============================================

def whatsapp_button(message):
    phone = "254707558206"
    encoded = urllib.parse.quote(message)
    link = f"https://wa.me/{phone}?text={encoded}"

    st.markdown(f"""
    <a href="{link}" target="_blank">
    <button style="
        background-color:#25D366;
        color:white;
        padding:14px 28px;
        border:none;
        border-radius:10px;
        font-size:18px;
        cursor:pointer;">
        📲 Send WhatsApp Alert
    </button>
    </a>
    """, unsafe_allow_html=True)

# ===============================================
# MAP
# ===============================================

def show_map(df):
    m = folium.Map(location=[lat, lon], zoom_start=15)

    for _, row in df.iterrows():

        color = "green"
        if row["severity"] == "Medium":
            color = "orange"
        elif row["severity"] == "High":
            color = "red"

        folium.Marker(
            location=[row["lat"], row["lon"]],
            popup=f"{row['damage']} | {row['severity']} | {row['time']}",
            icon=folium.Icon(color=color)
        ).add_to(m)

    st_folium(m, width=1000, height=500)

# ===============================================
# ANALYTICS
# ===============================================

def damage_chart(df):
    fig, ax = plt.subplots()
    df["damage"].value_counts().plot(kind="bar", ax=ax)
    ax.set_title("Damage Types")
    st.pyplot(fig)

def severity_chart(df):
    fig, ax = plt.subplots()
    df["severity"].value_counts().plot(kind="pie", autopct="%1.1f%%", ax=ax)
    ax.set_title("Severity Distribution")
    st.pyplot(fig)

def road_health_score(df):
    high = (df["severity"] == "High").sum()
    medium = (df["severity"] == "Medium").sum()
    return max(0, 100 - (high * 10 + medium * 5))

# ===============================================
# TABS
# ===============================================

tab1, tab2, tab3 = st.tabs(["🔍 Detection", "📄 Reports", "📊 Analytics"])

# ===============================================
# DETECTION TAB (FIXED BOUNDING BOXES)
# ===============================================

with tab1:

    st.subheader("Input Source")

    src = st.radio(
        "Choose Input",
        ["Upload Image"] + (["Camera"] if enable_camera else []),
        horizontal=True
    )

    file = None

    if src == "Upload Image":
        file = st.file_uploader("Upload Image", type=["jpg", "png", "jpeg"])

    if src == "Camera":
        file = st.camera_input("Capture Image")

    run = st.button("🚀 Run Detection", use_container_width=True)

    if run and file:

        with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
            tmp.write(file.read())
            path = tmp.name

        with st.spinner("Running AI Detection..."):
            results = model.predict(path, conf=confidence)[0]

        # ===============================
        # ✅ FIX: Bounding boxes visible
        # ===============================
        annotated_img = results.plot()
        annotated_img = cv2.cvtColor(annotated_img, cv2.COLOR_BGR2RGB)

        boxes = results.boxes.xyxy.cpu().numpy()
        clss = results.boxes.cls.cpu().numpy()

        rows = []

        for b, c in zip(boxes, clss):
            x1, y1, x2, y2 = b
            area = (x2 - x1) * (y2 - y1)

            rows.append({
                "damage": model.names[int(c)],
                "severity": severity(area),
                "area": int(area),
                "lat": lat,
                "lon": lon,
                "time": datetime.now()
            })

        df = pd.DataFrame(rows)

        st.session_state.df = df
        st.session_state.img = annotated_img

        # SHOW IMAGE WITH BOXES
        st.image(annotated_img, caption="Detected Road Damage", use_container_width=True)

# ===============================================
# RESULTS
# ===============================================

if st.session_state.df is not None:

    df = st.session_state.df

    st.divider()
    st.subheader("Detection Dashboard")

    if st.session_state.img is not None:
        st.image(st.session_state.img, caption="AI Detection Result", use_container_width=True)

    if df.empty:
        st.warning("No damage detected")
    else:

        c1, c2, c3, c4 = st.columns(4)

        c1.metric("Total", len(df))
        c2.metric("High", (df["severity"] == "High").sum())
        c3.metric("Medium", (df["severity"] == "Medium").sum())

        score = road_health_score(df)
        c4.metric("Health Score", f"{score}%")

        st.progress(score / 100)

        st.dataframe(df)

        message = f"""
🚨 ROAD DAMAGE ALERT
Location: {street_name}
High Severity: {(df["severity"] == "High").sum()}
Total: {len(df)}
"""

        whatsapp_button(message)

        st.subheader("Map")
        show_map(df)

# ===============================================
# REPORTS
# ===============================================

with tab2:

    st.subheader("Reports")

    if st.session_state.df is None:
        st.info("Run detection first")
    else:
        df = st.session_state.df

        st.download_button(
            "Download CSV",
            df.to_csv(index=False),
            "report.csv"
        )

# ===============================================
# ANALYTICS
# ===============================================

with tab3:

    st.subheader("Analytics")

    if os.path.exists("inspection_log.csv"):

        hist = pd.read_csv("inspection_log.csv")
        st.dataframe(hist)

        damage_chart(hist)
        severity_chart(hist)

        m = folium.Map(location=[lat, lon], zoom_start=13)

        heat_data = [[r["lat"], r["lon"]] for _, r in hist.iterrows()]
        HeatMap(heat_data).add_to(m)

        st_folium(m, width=1000, height=500)

    else:
        st.info("No history yet")