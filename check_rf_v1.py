import pandas as pd
import matplotlib.pyplot as plt

# 1. Load dataset
df = pd.read_csv("output/poc_features.csv")

# 2. Aggregate to session level
df["latency_first_response_sec"] = pd.to_numeric(df["latency_first_response_sec"], errors="coerce")

summary = []
for session_id, group in df.groupby("session_id"):
    feed_speed = group[group["phase"] == "FEED"]["avg_speed_norm_per_sec"].mean()
    pre_speed = group[group["phase"] == "PRE"]["avg_speed_norm_per_sec"].mean()
    latency = group["latency_first_response_sec"].dropna().median()
    label = group["appetite_label"].iloc[0]
    
    summary.append({
        "session_id": session_id,
        "PRE_speed": round(pre_speed, 4) if pd.notnull(pre_speed) else 0,
        "FEED_speed": round(feed_speed, 4) if pd.notnull(feed_speed) else 0,
        "latency_sec": latency,
        "appetite_label": label
    })

sum_df = pd.DataFrame(summary)

print("=" * 60)
print("SESSION BEHAVIOR SUMMARY TABLE")
print("=" * 60)
print(sum_df.to_string(index=False))

# 3. Plot 2D separation
plt.figure(figsize=(8, 5))
for label, color in zip(["High", "Low"], ["green", "red"]):
    subset = sum_df[sum_df["appetite_label"] == label]
    plt.scatter(subset["FEED_speed"], subset["latency_sec"], s=100, label=label, c=color)

plt.xlabel("FEED Phase Avg Speed (norm/sec)")
plt.ylabel("Latency to First Response (sec)")
plt.title("Session Separation: Speed vs Latency")
plt.legend()
plt.grid(True)
plt.savefig("output/session_separation.png")
print("\nSaved scatter plot to output/session_separation.png")