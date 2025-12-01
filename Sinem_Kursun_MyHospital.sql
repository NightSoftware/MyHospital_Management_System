-- ===================================================================
-- sinem_kursun_proje.sql
-- Hastane Yönetim Sistemi - PostgreSQL
-- Hazırlayan: Sinem Kurşun
--
-- Açıklama: Bu dosya PostgreSQL üzerinde tüm schema, fonksiyon, trigger,
-- prosedür, view, örnek veriler ve test sorgularını içerir.
--
-- Çalıştırma sırası:
--  1) DROP blokları (temizlik)
--  2) SEQUENCE (hasta numarası)
--  3) TABLOLAR
--  4) FONKSİYONLAR
--  5) TRIGGER FONKSİYONLARI + TRIGGERLAR
--  6) STORED PROCEDURE'LER
--  7) VIEW'LER
--  8) ÖRNEK VERİLER (INSERT)
--  9) TEST SORGULARI ve KOMPLEKS SORGULAR
--
-- Not: Eğer hata alırsanız, önce hangi satırda olduğunu kontrol edin.
-- ===================================================================

-- ===================================================================
-- 0) TEMİZLİK: Önceki objeleri kaldır (varsa)
-- ===================================================================
DROP VIEW IF EXISTS view_patients_history CASCADE;
DROP VIEW IF EXISTS view_doctors_appointments CASCADE;

DROP PROCEDURE IF EXISTS sp_create_prescription(JSONB, INTEGER, INTEGER, TEXT) CASCADE;
DROP PROCEDURE IF EXISTS sp_create_appointment(INTEGER, INTEGER, DATE, TIME, INTEGER, TEXT) CASCADE;

DROP FUNCTION IF EXISTS calculate_doctor_workload(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS patient_age(DATE) CASCADE;
DROP FUNCTION IF EXISTS available_doctors(INTEGER, DATE) CASCADE;

-- Triggers may not exist yet; DROP IF EXISTS safe.
DROP TRIGGER IF EXISTS trg_appointments_check_daily_limit ON appointments;
DROP TRIGGER IF EXISTS trg_prescriptions_set_date ON prescriptions;
DROP TRIGGER IF EXISTS trg_patients_generate_number ON patients;

DROP TABLE IF EXISTS prescription_details CASCADE;
DROP TABLE IF EXISTS prescriptions CASCADE;
DROP TABLE IF EXISTS appointments CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;
DROP TABLE IF EXISTS patients CASCADE;
DROP TABLE IF EXISTS doctors CASCADE;
DROP TABLE IF EXISTS departments CASCADE;

DROP SEQUENCE IF EXISTS seq_patient_number;

-- ===================================================================
-- 1) SEQUENCE ve TABLOLAR
-- ===================================================================

-- Hasta numarası için sequence (otomatik hasta numarası üretimi)
CREATE SEQUENCE seq_patient_number START 1000;

-- Bölümler (departments)
CREATE TABLE departments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    location VARCHAR(100)
);

-- Doktorlar (doctors)
CREATE TABLE doctors (
    id SERIAL PRIMARY KEY,
    department_id INTEGER NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
    first_name VARCHAR(80) NOT NULL,
    last_name VARCHAR(80) NOT NULL,
    email VARCHAR(150) UNIQUE,
    phone VARCHAR(30),
    daily_limit INTEGER NOT NULL DEFAULT 20,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Hastalar (patients)
CREATE TABLE patients (
    id SERIAL PRIMARY KEY,
    patient_number VARCHAR(20) UNIQUE NOT NULL, -- trigger ile atanacak
    first_name VARCHAR(80) NOT NULL,
    last_name VARCHAR(80) NOT NULL,
    birth_date DATE NOT NULL,
    gender VARCHAR(10),
    phone VARCHAR(30),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Randevular (appointments)
CREATE TABLE appointments (
    id SERIAL PRIMARY KEY,
    patient_id INTEGER NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    doctor_id INTEGER NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
    appointment_date DATE NOT NULL,
    appointment_time TIME NOT NULL,
    duration_minutes INTEGER NOT NULL DEFAULT 30,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Reçeteler (prescriptions)
CREATE TABLE prescriptions (
    id SERIAL PRIMARY KEY,
    patient_id INTEGER NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    doctor_id INTEGER REFERENCES doctors(id) ON DELETE SET NULL,
    prescription_date TIMESTAMP WITH TIME ZONE, -- trigger otomatik atar
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- İlaçlar (medicines)
CREATE TABLE medicines (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL UNIQUE,
    description TEXT
);

-- Reçete detayları (prescription_details)
CREATE TABLE prescription_details (
    id SERIAL PRIMARY KEY,
    prescription_id INTEGER NOT NULL REFERENCES prescriptions(id) ON DELETE CASCADE,
    medicine_id INTEGER NOT NULL REFERENCES medicines(id) ON DELETE RESTRICT,
    dosage VARCHAR(100),
    frequency VARCHAR(100),
    duration_days INTEGER
);

-- ===================================================================
-- 2) FONKSİYONLAR
-- ===================================================================

-- calculate_doctor_workload(doctor_id)
-- Açıklama: Verilen doktorun içinde bulunduğu ay için toplam randevu sayısını döner.
CREATE OR REPLACE FUNCTION calculate_doctor_workload(p_doctor_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM appointments
    WHERE doctor_id = p_doctor_id
      AND date_trunc('month', appointment_date) = date_trunc('month', CURRENT_DATE);
    RETURN COALESCE(v_count, 0);
END;
$$;

-- patient_age(birth_date)
-- Açıklama: Doğum tarihinden tam yaşı hesaplar (yıl)
CREATE OR REPLACE FUNCTION patient_age(p_birth_date DATE)
RETURNS INTEGER
LANGUAGE sql
AS $$
    SELECT DATE_PART('year', AGE(CURRENT_DATE, p_birth_date))::INTEGER;
$$;

-- available_doctors(department_id, appointment_date)
-- Açıklama: Belirli bölümde ve tarihte günlük limiti dolmamış, aktif doktorları listeler.
CREATE OR REPLACE FUNCTION available_doctors(p_department_id INTEGER, p_date DATE)
RETURNS TABLE(id INTEGER, first_name VARCHAR, last_name VARCHAR, daily_limit INTEGER)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT d.id, d.first_name, d.last_name, d.daily_limit
    FROM doctors d
    WHERE d.department_id = p_department_id
      AND d.active = TRUE
      AND (
          SELECT COUNT(*) FROM appointments a
          WHERE a.doctor_id = d.id
            AND a.appointment_date = p_date
      ) < d.daily_limit;
END;
$$;

-- ===================================================================
-- 3) TRIGGER FONKSİYONLARI ve TRIGGERLAR
-- ===================================================================

-- 3.1 Randevu eklenmeden önce doktorun günlük limitini kontrol eden trigger fonksiyonu
CREATE OR REPLACE FUNCTION fn_appointments_check_daily_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
    v_limit INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM appointments
    WHERE doctor_id = NEW.doctor_id
      AND appointment_date = NEW.appointment_date;

    SELECT daily_limit INTO v_limit FROM doctors WHERE id = NEW.doctor_id;

    IF v_limit IS NULL THEN
        RAISE EXCEPTION 'Doctor id % does not exist', NEW.doctor_id;
    END IF;

    IF v_count >= v_limit THEN
        RAISE EXCEPTION 'Doctor (id=%) has reached daily limit (%) for %', NEW.doctor_id, v_limit, NEW.appointment_date;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_appointments_check_daily_limit
BEFORE INSERT ON appointments
FOR EACH ROW
EXECUTE FUNCTION fn_appointments_check_daily_limit();

-- 3.2 Reçete oluşturulurken prescription_date otomatik atanır
CREATE OR REPLACE FUNCTION fn_prescriptions_set_date()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.prescription_date IS NULL THEN
        NEW.prescription_date := now();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prescriptions_set_date
BEFORE INSERT ON prescriptions
FOR EACH ROW
EXECUTE FUNCTION fn_prescriptions_set_date();

-- 3.3 Hasta eklendiğinde patient_number üreten trigger
-- Format: 'P' + 6 haneli sequence (ör: P001000)
CREATE OR REPLACE FUNCTION fn_patients_generate_number()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.patient_number IS NULL OR NEW.patient_number = '' THEN
        NEW.patient_number := 'P' || LPAD(nextval('seq_patient_number')::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_patients_generate_number
BEFORE INSERT ON patients
FOR EACH ROW
EXECUTE FUNCTION fn_patients_generate_number();

-- ===================================================================
-- 4) STORED PROCEDURE'LER
-- ===================================================================

-- sp_create_appointment
-- Açıklama: Randevu oluşturur. Trigger günlük limiti kontrol eder.
CREATE OR REPLACE PROCEDURE sp_create_appointment(
    p_patient_id INTEGER,
    p_doctor_id INTEGER,
    p_appointment_date DATE,
    p_appointment_time TIME,
    p_duration_minutes INTEGER,
    p_notes TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO appointments(patient_id, doctor_id, appointment_date, appointment_time, duration_minutes, notes)
    VALUES (p_patient_id, p_doctor_id, p_appointment_date, p_appointment_time, p_duration_minutes, p_notes);
END;
$$;

-- sp_create_prescription
-- Açıklama: Reçete oluşturur ve JSONB ile gelen ilaç listesini prescription_details'e ekler.
-- meds_json formatı: [ {"medicine_id":1, "dosage":"500mg", "frequency":"günde 3", "duration_days":5}, ... ]
CREATE OR REPLACE PROCEDURE sp_create_prescription(
    meds_json JSONB,
    p_patient_id INTEGER,
    p_doctor_id INTEGER,
    p_notes TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_prescription_id INTEGER;
    item JSONB;
    med_id INTEGER;
    dosage TEXT;
    frequency TEXT;
    duration_days INTEGER;
BEGIN
    INSERT INTO prescriptions(patient_id, doctor_id, notes)
    VALUES (p_patient_id, p_doctor_id, p_notes)
    RETURNING id INTO v_prescription_id;

    FOR item IN SELECT * FROM jsonb_array_elements(meds_json) LOOP
        med_id := (item ->> 'medicine_id')::INTEGER;
        dosage := item ->> 'dosage';
        frequency := item ->> 'frequency';
        duration_days := NULLIF(item ->> 'duration_days','')::INTEGER;

        INSERT INTO prescription_details(prescription_id, medicine_id, dosage, frequency, duration_days)
        VALUES (v_prescription_id, med_id, dosage, frequency, duration_days);
    END LOOP;
END;
$$;

-- ===================================================================
-- 5) VIEW'LER
-- ===================================================================

-- Doktorların toplam randevu sayıları ve bölümleriyle birlikte
CREATE OR REPLACE VIEW view_doctors_appointments AS
SELECT d.id AS doctor_id,
       d.first_name || ' ' || d.last_name AS doctor_name,
       dep.name AS department_name,
       COUNT(a.id) AS total_appointments
FROM doctors d
LEFT JOIN appointments a ON a.doctor_id = d.id
JOIN departments dep ON dep.id = d.department_id
GROUP BY d.id, d.first_name, d.last_name, dep.name;

-- Hastaların randevu geçmişi detaylı view
CREATE OR REPLACE VIEW view_patients_history AS
SELECT p.id AS patient_id,
       p.patient_number,
       p.first_name,
       p.last_name,
       a.id AS appointment_id,
       a.appointment_date,
       a.appointment_time,
       a.duration_minutes,
       d.first_name || ' ' || d.last_name AS doctor_name,
       dep.name AS department_name,
       pr.id AS prescription_id,
       pr.prescription_date
FROM patients p
LEFT JOIN appointments a ON a.patient_id = p.id
LEFT JOIN doctors d ON d.id = a.doctor_id
LEFT JOIN departments dep ON dep.id = d.department_id
LEFT JOIN prescriptions pr ON pr.patient_id = p.id
ORDER BY p.id, a.appointment_date DESC NULLS LAST;

-- ===================================================================
-- 6) ÖRNEK VERİLER (EN AZ 10 ÖRNEK) - INSERT STATEMENTS
-- Tüm örnek veriler "daha doğal" isimlendirme ile güncellendi.
-- ===================================================================

-- Bölümler (4 kayıt)
INSERT INTO departments(name, location) VALUES
('Kardiyoloji', 'B Blok'),
('Dahiliye', 'A Blok'),
('Ortopedi', 'C Blok'),
('Kulak Burun Boğaz', 'D Blok');

-- Doktorlar (6 kayıt)
INSERT INTO doctors(department_id, first_name, last_name, email, phone, daily_limit) VALUES
(1, 'Levent', 'Ertaş', 'l.ertas@hastane.com', '05510034211', 10),
(1, 'Nazlı', 'Çeliker', 'n.celiker@hastane.com', '05512099833', 12),
(2, 'Hakan', 'Uslu', 'h.uslu@hastane.com', '05517765422', 14),
(3, 'Gülcan', 'Önen', 'g.onen@hastane.com', '05513329012', 8),
(4, 'Serdar', 'Irgat', 's.irgat@hastane.com', '05519874561', 9),
(2, 'Meral', 'Karabeyoğlu', 'm.karabeyoglu@hastane.com', '05516003477', 11);

-- Hastalar (8 kayıt)  -- patient_number tetiklenerek atanacak
INSERT INTO patients(first_name, last_name, birth_date, gender, phone) VALUES
('Okan', 'Ermiş', '1982-03-11', 'Erkek', '05324556621'),
('Seda', 'Kumral', '1994-09-05', 'Kadın', '05381245598'),
('Mahir', 'Aksoylu', '1976-02-19', 'Erkek', '05372389012'),
('Dilara', 'Uzun', '2001-11-23', 'Kadın', '05368944123'),
('Yaren', 'Güçlü', '2012-07-18', 'Kadın', '05375500987'),
('Koray', 'Diker', '1999-04-01', 'Erkek', '05393320144'),
('Esra', 'Konuk', '1987-05-29', 'Kadın', '05324410022'),
('Tamer', 'Sarıoğlu', '1968-01-14', 'Erkek', '05333490900');

-- İlaçlar (5 kayıt)
INSERT INTO medicines(name, description) VALUES
('Dolorin 500mg', 'Ağrı ve ateş için'),
('Augmentin 625mg', 'Geniş spektrum antibiyotik'),
('Nurofen 200mg', 'İltihap azaltıcı'),
('Lansor 30mg', 'Mide koruyucu'),
('Rosvera 20mg', 'Kolesterol düzenleyici');

-- Randevular (10 kayıt)
INSERT INTO appointments(patient_id, doctor_id, appointment_date, appointment_time, duration_minutes, notes) VALUES
(1, 1, CURRENT_DATE, '09:10', 25, 'Göğüs sıkışması şikayeti'),
(2, 1, CURRENT_DATE, '10:00', 30, 'Kontrol muayenesi'),
(3, 2, CURRENT_DATE + 1, '11:45', 40, 'Nabız düzensizliği'),
(4, 3, CURRENT_DATE + 3, '14:20', 30, 'Mide yanması'),
(5, 4, CURRENT_DATE, '15:00', 15, 'Kulak tıkanıklığı'),
(6, 2, CURRENT_DATE - 8, '09:00', 30, 'Geçmiş randevu - kontrol'),
(7, 3, CURRENT_DATE - 4, '13:30', 30, 'Eklem ağrısı'),
(8, 1, CURRENT_DATE - 19, '16:10', 30, 'Takip muayenesi'),
(1, 2, CURRENT_DATE + 6, '10:40', 30, 'Reflü şikayeti'),
(2, 3, CURRENT_DATE + 4, '16:20', 25, 'Düzenli kontrol');

-- Reçeteler (4 kayıt) ve detayları (5 kayıt)
INSERT INTO prescriptions(patient_id, doctor_id, prescription_date, notes) VALUES
(1, 1, now() - INTERVAL '5 days', 'Ateş ve kas ağrısı için önerildi'),
(2, 1, now() - INTERVAL '2 days', 'Bakteriyel enfeksiyon şüphesi'),
(3, 2, NULL, 'Düzenli kullanım önerildi'),  -- trigger tarih atayacak
(5, 4, NULL, 'Kulak içi enfeksiyon nedeniyle reçete'); -- trigger tarih atayacak

INSERT INTO prescription_details(prescription_id, medicine_id, dosage, frequency, duration_days) VALUES
(1, 1, '500mg', 'günde 3 kez', 3),
(1, 3, '200mg', 'günde 2 kez', 4),
(2, 2, '625mg', 'günde 2 kez', 7),
(3, 5, '20mg', 'günde 1 kez', 30),
(4, 1, '500mg', 'günde 2 kez', 5);

-- ===================================================================
-- 7) TEST SORGULARI (HER FONKSİYON/TRIGGER/PROCEDURE İÇİN)
-- ===================================================================

-- 7.1 Fonksiyon testleri

-- calculate_doctor_workload: doktor id = 1 için bu ayki randevu sayısını hesapla
SELECT calculate_doctor_workload(1) AS doctor_1_monthly_appointments;

-- patient_age: ilk 5 hastanın yaşlarını göster
SELECT id, first_name, last_name, birth_date, patient_age(birth_date) AS age
FROM patients ORDER BY id LIMIT 5;

-- available_doctors: Kardiyoloji bölümündeki (department_id = 1) bugünkü müsait doktorlar
SELECT * FROM available_doctors(1, CURRENT_DATE);

-- 7.2 Trigger testleri

-- Randevu günlük limit kontrolü: sp_create_appointment ile normal ekleme
CALL sp_create_appointment(1, 1, CURRENT_DATE + 10, '10:00', 30, 'Test randevu prosedür');

-- Reçete tarih otomatik atama: prescription_date NULL bırakan bir insert yapıldı; trigger atayacak
INSERT INTO prescriptions(patient_id, doctor_id, notes) VALUES (6, 2, 'Tetikleme testi - tarih atama');
SELECT id, patient_id, doctor_id, prescription_date FROM prescriptions WHERE patient_id = 6 ORDER BY id DESC LIMIT 1;

-- Hasta ekleme patient_number otomatik ataması
INSERT INTO patients(first_name, last_name, birth_date, gender) VALUES ('Deneme', 'Kullanici', '1999-05-05', 'Erkek');
SELECT id, patient_number, first_name, last_name FROM patients WHERE first_name = 'Deneme' AND last_name = 'Kullanici' ORDER BY id DESC LIMIT 1;

-- 7.3 Stored procedure testleri

-- sp_create_appointment (CALL örneği)
CALL sp_create_appointment(7, 4, CURRENT_DATE + 4, '09:00', 30, 'Prosedür ile randevu');
SELECT * FROM appointments WHERE appointment_date = CURRENT_DATE + 4 AND doctor_id = 4;

-- sp_create_prescription (CALL örneği) - JSONB ilaç listesi ile
DO $$
DECLARE
    meds JSONB := '[{"medicine_id":1, "dosage":"500mg","frequency":"günde 3","duration_days":3}, {"medicine_id":4, "dosage":"30mg","frequency":"günde 1","duration_days":14}]'::JSONB;
BEGIN
    CALL sp_create_prescription(meds, 8, 2, 'Prosedür ile reçete örneği');
END$$;

-- 7.4 View testleri
SELECT * FROM view_doctors_appointments ORDER BY total_appointments DESC LIMIT 10;
SELECT * FROM view_patients_history WHERE patient_id = 1 LIMIT 20;

-- ===================================================================
-- 8) KOMPLEKS SORGULAR
-- ===================================================================

-- Bölümlere göre hasta sayıları (distinct) ve ortalama randevu süreleri
SELECT dep.id AS department_id, dep.name AS department_name,
       COUNT(DISTINCT a.patient_id) AS patient_count,
       AVG(a.duration_minutes)::NUMERIC(10,2) AS avg_appointment_duration
FROM departments dep
LEFT JOIN doctors d ON d.department_id = dep.id
LEFT JOIN appointments a ON a.doctor_id = d.id
GROUP BY dep.id, dep.name
ORDER BY patient_count DESC;

-- En çok reçete yazılan ilaçlar (GROUP BY + HAVING)
SELECT m.id, m.name, COUNT(pd.id) AS prescription_count
FROM medicines m
JOIN prescription_details pd ON pd.medicine_id = m.id
GROUP BY m.id, m.name
HAVING COUNT(pd.id) >= 1
ORDER BY prescription_count DESC;

-- Ortalamadan fazla randevusu olan doktorlar (aylık)
SELECT doctor_id, doctor_name, total_appointments
FROM (
    SELECT d.id AS doctor_id,
           d.first_name || ' ' || d.last_name AS doctor_name,
           COUNT(a.id) FILTER (WHERE date_trunc('month', a.appointment_date) = date_trunc('month', CURRENT_DATE)) AS total_appointments
    FROM doctors d
    LEFT JOIN appointments a ON a.doctor_id = d.id
    GROUP BY d.id
) t
WHERE total_appointments > (
    SELECT AVG(total_appointments) FROM (
        SELECT COUNT(a2.id) FILTER (WHERE date_trunc('month', a2.appointment_date) = date_trunc('month', CURRENT_DATE)) AS total_appointments
        FROM doctors d2
        LEFT JOIN appointments a2 ON a2.doctor_id = d2.id
        GROUP BY d2.id
    ) sub
);


