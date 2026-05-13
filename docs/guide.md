# 🧹 Panduan Lengkap Membersihkan Drive C:

> **Target pembaca:** User non-teknis, orang kantoran, mahasiswa
> **Level:** Pemula — tinggal ikutin langkah demi langkah

---

## 📋 Sebelum Mulai

**Yang perlu disiapkan:**
- Laptop/PC Windows (10 atau 11)
- 5-10 menit waktu luang
- Gak perlu install software tambahan

**Aturan emas:**
> Yang bukan buatan kamu → jangan dihapus kalo gak yakin.
> File di **Downloads** → cek dulu, baru hapus.

---

## 🔧 Metode 1: Paling Gampang (Disk Cleanup Bawaan Windows)

Ini cara termudah. Windows punya tool pembersih sendiri.

**Langkah:**
1. Tekan **`Win + R`** (tombol Windows + R)
2. Ketik **`cleanmgr`** → Enter
3. Pilih drive **C:** → klik OK
4. Windows bakal scan, tunggu bentar
5. Klik tombol **"Clean up system files"** (butuh admin, nanti minta izin)
6. Centang item-item ini:
   - ☑ **Windows Update Cleanup** *(paling gede, biasanya 2-5 GB)*
   - ☑ **Delivery Optimization Files**
   - ☑ **Temporary Internet Files** *(cache browser)*
   - ☑ **Recycle Bin**
   - ☑ **Temporary Files**
7. Klik **OK** → **Delete Files**

**Hasil:** Biasanya dapet **3-8 GB** langsung.

---

## 🔧 Metode 2: Bersihin Temp Manual

Folder Temp isinya sampah sementara — aplikasi lupa bersihin sendiri.

**Langkah:**
1. Tekan **`Win + R`**
2. Ketik **`%temp%`** → Enter
3. Folder terbuka, isinya banyak file/folder
4. Tekan **`Ctrl + A`** (select all)
5. Tekan **`Shift + Delete`** (hapus permanen, gak masuk Recycle Bin)
6. Kalo ada error "file sedang dipake" → klik **Skip**
7. Selesai

**Hasil:** Biasanya **2-5 GB** tambahan.

> 💡 **Tips:** Kalo banyak file kecil, hapusnya bisa lama. Sabar ya.

---

## 🔧 Metode 3: Browser Cache

Chrome / Edge numpuk cache biar website cepet dibuka. Tapi lama-lama numpuk.

### Google Chrome
1. Buka Chrome
2. Klik **⋮** (3 titik kanan atas)
3. Pilih **More Tools** → **Clear Browsing Data**
4. Atau shortcut: **`Ctrl + Shift + Del`**
5. Atur:
   - **Time range:** All time
   - Centang: ☑ **Cached images and files**
6. Klik **Clear data**

### Microsoft Edge
1. Buka Edge
2. Klik **⋯** (3 titik kanan atas)
3. Pilih **Settings** → **Privacy, search, and services**
4. Di bagian **Clear browsing data**, klik **Choose what to clear**
5. Centang **Cached images and files**
6. Klik **Clear now**

**Hasil:** **200-500 MB** per browser.

---

## 🔧 Metode 4: npm Cache (Kalo kamu programmer)

Kalo laptop ini dipake coding, npm cache bisa makan banyak.

**Langkah:**
1. Buka **PowerShell** atau **Command Prompt**
2. Ketik:
```powershell
npm cache clean --force
```
3. Enter, tunggu selesai

**Hasil:** Bisa **5-10 GB** langsung ilang.

> 💡 Kalo belum pernah install npm di laptop ini, skip aja.

---

## 🔧 Metode 5: Cek Downloads

Biasanya ini yang paling gede — bertahun-tahun download numpuk.

**Langkah:**
1. Buka **File Explorer** → klik **Downloads** di sidebar kiri
2. Atau buka: **`C:\Users\bagia\Downloads`**
3. Urutkan dari yang terbesar:
   - Klik kanan di kolom → pilih **Sort by** → **Size**
   - Kalo gak ada kolom Size, klik **View** → **Details**
4. Hapus file yang udah gak dipake:
   - Installer `.exe`, `.msi` — kalo udah keinstall, hapus aja
   - File `.zip`, `.rar` — kalo udah di-extract, hapus aja
   - File PDF/document — cek dulu, kalo penting pindahin ke Documents
5. **Shift + Delete** buat hapus permanen

**Hasil:** Bisa **10-20 GB** kalo jarang dibersihin.

---

## 🔧 Metode 6: Aplikasi Lain

### Zoom Cache (~1 GB)
- Buka: **`C:\Users\bagia\AppData\Roaming\Zoom`**
- Hapus folder: **`meeting_logs`**, **`data`**, **`cache`**

### CapCut Cache (~7 GB)
- Buka: **`C:\Users\bagia\AppData\Local\CapCut`**
- Cari folder **`draft`**, **`cache`** atau apapun yang gede
- Hapus project video yang udah selesai/exported

### 3uTools Backup (~6 GB)
- Buka: **`C:\3uTools`**
- Cek isinya — kalo itu backup iPhone lama, hapus aja
- Tapi **pastikan** backup iPhonenya udah gak diperlukan

---

## 📊 Estimasi Total

| Langkah | Perkiraan |
|---------|-----------|
| Disk Cleanup | 3-8 GB |
| Temp Manual | 2-5 GB |
| Browser Cache | 0,2-0,5 GB |
| npm cache* | 5-10 GB |
| Downloads | 10-20 GB |
| Aplikasi lain | 5-15 GB |
| **Total potensi** | **25-60 GB** ✨ |

> *Kalo ada

---

## ⚠️ Peringatan

| ❌ Jangan dihapus | ✅ Boleh dihapus |
|-----------------|-----------------|
| `C:\Windows` | `C:\Windows\Temp` |
| `C:\Program Files` | `%temp%` |
| `C:\Users\bagia\Documents` | File Downloads (setelah dicek) |
| File `.dll`, `.sys` | File `.exe` installer |
| Folder aplikasi (Chrome, Office) | Cache & log aplikasi |

---

## 🆘 Masih Penuh? Coba Ini

1. **Uninstall aplikasi gak kepake**
   - Settings → Apps → Installed apps → urutkan dari terbesar
   - Hapus yang udah gak dipake

2. **Pindahkan file besar ke drive lain** (kalo ada D: atau E:)
   - Pindahin folder Videos, Music, atau Documents ke D:

3. **Matikan Hibernation** (kalo gak pake)
   - Buka PowerShell (Admin):
   ```powershell
   powercfg /h off
   ```
   - Ini bisa bebasin **3-6 GB**

4. **Kecilin System Restore**
   - Settings → System → About → System Protection
   - Kurangi penggunaan disk (misal 5% aja)

---

> Panduan ini bagian dari **DrivePulse** 🧹
> Butuh bantuan? Chat Yombi 🦥 atau hubungi @rheriprasetyo
