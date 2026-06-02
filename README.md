# 📩 MikroTik SMS to Telegram Forwarder

[![RouterOS](https://img.shields.io/badge/RouterOS-7.22-blue.svg)](https://mikrotik.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

A script for **MikroTik RouterOS** that reads incoming SMS messages from a 3G/4G USB modem and forwards them to Telegram. This script solves multiple issues found in standard implementations, such as incorrect character encoding, missing parts of long messages, and garbage service SMS.

## ✨ Features

* **Smart Concatenation:** Long (multipart) SMS messages are stitched together and delivered to Telegram as a single, complete message.
* **Correct 7-bit UDH Handling:** Fixes the issue where characters were lost or garbled when decoding multipart messages.
* **Auto-detect Port:** The script automatically finds the active modem `ppp-client` interface (can be disabled to set it manually).
* **Suspicious Number Tagging:** Allows you to define a list of numbers (e.g., short spam numbers) that will be flagged with a ⚠️ emoji.
* **Binary Data Handling:** Operator service messages (Push, WAP, configuration) are tagged with ⚙️ `[OPERATOR BINARY FILE]` and do not break the script.
* **Memory Cleanup:** After a successful Telegram delivery, SMS messages are automatically deleted from the SIM card to prevent memory overflow.

## 🛠 Compatibility & Testing

The script has been successfully tested on the following hardware and software:
* **OS:** MikroTik RouterOS v7.22
* **Modem:** Huawei E3372h (Stick mode, `ppp-client` interface)

*Note: The script operates via AT commands. Make sure your modem is in Stick mode (PPP), not HiLink mode (LTE interface), as HiLink modems handle SMS via their own web interface.*

## 🚀 Installation

### Step 1: Telegram Setup
1. Message [@BotFather](https://t.me/BotFather) on Telegram and create a new bot using the `/newbot` command.
2. Copy the provided **Bot Token**.
3. Message [@userinfobot](https://t.me/userinfobot) (or a similar bot) to find out your **Chat ID** (where the bot will send the SMS). 
4. Press `/start` in the chat with your newly created bot to allow it to message you.

### Step 2: RouterOS Setup
1. Connect to your MikroTik (via Winbox or WebFig).
2. Go to `System` -> `Scripts`.
3. Click `+` (Add) to create a new script.
4. In the **Name** field, enter `sms_to_telegram`.
5. Check the following **Policies**: `read`, `write`, `policy`, `test`.
6. Paste the script code into the large text area (**Source**).
7. Edit the settings block at the very beginning of the script:

```routeros
# --- SETTINGS BLOCK ---
:local botToken "YOUR_BOT_TOKEN_HERE"
:local chatId "YOUR_CHAT_ID_HERE"

:local autoDetectPort true
:local usbPort "usb1"

# List of suspicious numbers (comma-separated, no spaces)
:local suspiciousNumbers "888,000"
# ---------------------
```

**Settings Explanation:**
* **`botToken` & `chatId`**: Your Telegram bot credentials obtained in Step 1.
* **`autoDetectPort` (`true` / `false`)**: Set to `true` to let the script automatically find your active `ppp-client` interface. 
* **`usbPort`**: If `autoDetectPort` is set to `false`, manually specify your modem's USB port name here (e.g., `"usb1"`).
* **`suspiciousNumbers`**: A comma-separated list of phone numbers (no spaces). If an SMS arrives from one of these numbers, the script will prepend a ⚠️ `[SUSPICIOUS NUMBER]` tag to the Telegram message. This is highly useful for highlighting spam, short-code alerts, or promotional messages.

8. Click **Apply** and **OK**.

### Step 3: Scheduler Setup
To make the script check for SMS automatically, you need to add it to the scheduler to run once a minute.

**Option A: Via Terminal (CLI)**
You can simply paste this code into the MikroTik Terminal:
```routeros
/system scheduler
add interval=1m name=check_sms on-event=sms_to_telegram policy=read,write,policy,test
```

**Option B: Via Winbox/WebFig**
1. Go to `System` -> `Scheduler`.
2. Click `+` (Add).
3. In the **Name** field, enter `check_sms`.
4. In the **Interval** field, set the check frequency to `00:01:00` (every 1 minute).
5. In the **On Event** field, enter the name of your script: `sms_to_telegram`.
6. Click **Apply** and **OK**.
