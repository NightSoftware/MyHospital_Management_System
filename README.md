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

Notlar 📝

SQL dosyası, tüm schema, trigger, fonksiyon, prosedür, view, örnek veri ve test sorgularını içerir.

Çalıştırma sırası dosya içinde belirtilmiştir: DROP → SEQUENCE → TABLOLAR → FONKSİYON → TRIGGER → PROCEDURE → VIEW → ÖRNEK VERİ → TEST SORGULARI → KOMPLEKS SORGULAR

Hatalarla karşılaşırsanız, önce ilgili satırları ve sıralamayı kontrol edin.
