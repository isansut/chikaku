# Chikaku — Share Live 24 Jam (2 Orang)

**Chikaku** adalah aplikasi Android untuk berbagi lokasi live 24 jam khusus berdua (seperti Live Location WhatsApp), lengkap dengan jarak real-time, estimasi waktu tempuh, chat, voice note, status/colek, dan tampilan peta modern berbasis OpenStreetMap.

## Fitur Utama
- **Live Location 24 Jam**: Timer hitung mundur 24 jam dengan opsi perpanjang/reset dan jeda (pause) kapan saja.
- **Jarak & Estimasi Real-time**: Menampilkan jarak akurat (`m` / `km`), estimasi waktu tempuh, garis penghubung di peta, dan indikator baterai pasangan.
- **Voice Note & Chat**: Rekam dan kirim voice note langsung dari layar peta, lengkap dengan pemutar audio dan balasan cepat.
- **Colek / Ping**: Kirim notifikasi singkat (`👋 Colek`, `❤️ Kangen`) ke pasangan.
- **Mode Demo (1 HP)**: Bisa langsung dicoba di 1 HP dengan simulasi pasangan bergerak di peta.
- **Mode Online (2 HP)**: Terhubung secara real-time melalui server Node.js WebSocket.

## Menjalankan Server WebSocket (Untuk 2 HP)
```bash
cd server
npm install
npm start
```
Server berjalan di port `3000`. Gunakan IP LAN (mis. `ws://192.168.1.10:3000`) untuk jaringan Wi-Fi yang sama, atau expose menggunakan Ngrok / VPS (`wss://...`) untuk jaringan internet berbeda.
