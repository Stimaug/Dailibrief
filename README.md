# DailyBrief (Flutter)

Implementasi aplikasi DailyBrief sesuai SKPPL (Bab VI Perancangan Antarmuka), bertema putih dan simpel.

| Bab 6 | State (Tabel 4.23) | Implementasi |
|---|---|---|
| 6.1 Layar Pembuka | - | `screens/splash_screen.dart` |
| 6.2 Siap Digunakan | Idle | `HomeScreen` (`VoiceState.idle`) |
| 6.3 Mendengarkan | Listening | `HomeScreen` (`VoiceState.listening`) |
| 6.4 Memproses | Processing / Fetching Data | `HomeScreen` (`VoiceState.processing`) |
| 6.5 Berbicara / Hasil | Speaking | `HomeScreen` (`VoiceState.speaking`) + kartu hasil |
| 6.6 Terjadi Kesalahan | Error | `HomeScreen` (`VoiceState.error`) |

Kelas pendukung sesuai class diagram: `VoiceCommandController`, `SpeechService`, `TtsService`, `CommandService` (`CommandType`), `LocationService`, `WeatherService`, `ErrorHandler`, `ErrorType`.

Fitur Aksesibilitas, Riwayat, dan Bantuan tidak dipakai; seluruh sisa kodenya (pembungkus `Semantics`, dll.) sudah dihapus.

## Cara menjalankan di Android Studio

Folder `android/` di sini hanya berisi `AndroidManifest.xml` (izin RECORD_AUDIO, INTERNET, ACCESS_FINE_LOCATION) karena proyek Android lengkap harus dibuat oleh Flutter tool itu sendiri. Langkah paling aman:

1. Buat proyek Flutter kosong:
   ```
   flutter create --org com.dailybrief --project-name dailybrief dailybrief_app
   ```
2. Salin isi folder `lib/` dari sini ke dalam `dailybrief_app/lib/` (timpa `main.dart` yang ada).
3. Salin `pubspec.yaml` dari sini ke `dailybrief_app/pubspec.yaml` (timpa yang ada, lalu sesuaikan bagian `flutter:` assets jika Anda menambah aset sendiri).
4. Salin isi `<manifest>...</manifest>` dari `android/app/src/main/AndroidManifest.xml` di sini ke dalam file yang sama pada `dailybrief_app/android/app/src/main/AndroidManifest.xml` (gabungkan permission & `<queries>` ke manifest yang sudah ada, jangan menimpa seluruh file).
5. Set `minSdkVersion` ke minimal **23** di `dailybrief_app/android/app/build.gradle` (dibutuhkan oleh `speech_to_text` & `geolocator`).
6. Jalankan:
   ```
   cd dailybrief_app
   flutter pub get
   flutter run
   ```
7. Buka di Android Studio via `File > Open` pada folder `dailybrief_app`.

## Catatan teknis

- **Lokasi (100% gratis, tanpa API key)**: posisi dari GPS akurasi tinggi; alamat sampai jalan dari **OpenStreetMap Nominatim** (reverse geocoding zoom 18). Nama tempat/kota (mis. "Medan") dicari lewat Nominatim, cadangan **Open-Meteo Geocoding**. Google Maps sudah dihapus.
- **Cuaca**: pertanyaan dibaca per tanggal dan per tempat.
  - Hari ini: kondisi saat ini dari **BMKG** (per kelurahan/desa dari lokasi GPS), cadangan Open-Meteo.
  - Besok sampai 3 hari: prakiraan harian BMKG (suhu min-maks, waktu hujan); bila tempat yang disebut hanya nama kota atau BMKG gagal, memakai **Open-Meteo**.
  - 4-15 hari ke depan dan masa lalu sampai 90 hari: **Open-Meteo** (suhu min-maks, peluang hujan).
  - Lebih jauh dari 15 hari (mis. "10 Desember" saat ini bulan Oktober): tidak ada prakiraan yang akurat, sehingga aplikasi mengatakannya terus terang dan memberi **rata-rata historis 5 tahun terakhir** (suhu dan persentase hari hujan) dari arsip Open-Meteo.
  - Sumber data selalu ditampilkan di kartu hasil (BMKG wajib; Open-Meteo CC BY 4.0).
- **Contoh pertanyaan cuaca**: "cuaca", "cuaca besok", "cuaca besok di Medan", "cuaca tanggal 10 Desember", "sepuluh desember di Medan", "tiga hari lagi", "hari Rabu", "apakah besok hujan di Batam", "cuaca lusa di sini".
- Contoh perintah lain: "lokasi saya", "jalan apa ini", "alamat saya", "lokasi Politeknik Negeri Batam", "hari apa besok", "tanggal 25 Desember hari apa".
- **Bahasa**: locale suara & TTS diset ke `id_ID` / `id-ID`. Pastikan perangkat pengujian memiliki Google Text-to-Speech dan paket bahasa Indonesia terpasang, serta koneksi internet aktif untuk speech recognition & cuaca.
- **Firebase** (Analytics & Crashlytics pada SKPPL) belum dipasang karena membutuhkan `google-services.json` dari proyek Firebase tim.

## Struktur folder
```
lib/
  main.dart
  theme/app_theme.dart
  widgets/brand.dart
  controllers/voice_command_controller.dart
  models/error_type.dart
  services/{speech,tts,command,weather,bmkg,location,error_handler}_service.dart
  screens/{splash,home}_screen.dart
```
