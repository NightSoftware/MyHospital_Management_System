🏥 Hospital Management System (PostgreSQL)

Bu repo, örnek bir hastane yönetim sisteminin veritabanı yapısını içeriyor. Doktorlar, hastalar, randevular ve reçeteler gibi temel işlevleri kapsayan  bir şema oluşturdum.

📌 İçerik

-PostgreSQL için tablo oluşturma scriptleri

-İçinde örnek veriler olan seed dosyası

-DrawSQL tarzında hazırlanmış (PNG) 

-Anlaşılır bir veritabanı tasarımı

🗄️ Veritabanı Yapısı

Proje toplam 7 tablodan oluşuyor:

departments – Hastane bölümleri

doctors – Doktor bilgileri

patients – Hasta kayıtları

appointments – Randevular

medicines – Sistem genelinde kullanılan ilaçlar

prescriptions – Reçetelerin ana tablosu

prescription_details – Reçeteye eklenen ilaç satırları

Özetle:
Doktor → Randevu → Reçete → İlaçlar
takip eden bir yapı.
