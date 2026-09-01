# OpenEQ Precision Monitor Controller Planı

## Amaç

OpenEQ’yu ölçülebilir, güvenli ve seviye-eşlemeli çalışan bir monitör kontrol ve kalibrasyon istasyonuna dönüştürmek. Yerel oynatma kararlı ana yol olarak kalır; CATap tabanlı sistem-geneli EQ deneysel olarak etiketlenir.

## Tasarım ilkeleri

- EQ kararları her zaman doğru gain staging ve loudness matching ile karşılaştırılır.
- Limiter son güvenlik katmanıdır; kötü preamp ayarını gizleyen sürekli bir işlemci olmamalıdır.
- Ses callback’lerinde allocation, lock ve UI erişimi yapılmaz.
- Bypass, preset ve cihaz değişimleri ramp/crossfade ile tıklamasız gerçekleşir.
- Fiziksel çıkış veya izin kaybında orijinal çıkış güvenli biçimde geri yüklenir.

## Fazlar

### Faz 0 — Sözleşme ve ölçüm modeli

Yeni ortak ölçüm veri modeli tanımlanır: L/R peak, RMS, true-peak tahmini, headroom, limiter gain reduction ve clipping durumu. DSP callback’i yalnızca önceden ayrılmış atomik/lock-free snapshot alanını günceller; UI bu snapshot’ı periyodik okur.

Kabul kriterleri: stereo ve mono yollar aynı ölçüm semantiğini kullanır; sessizlikte seviyeler `−∞`; callback’te heap allocation yoktur.

### Faz 1 — Otomatik headroom ve limiter telemetrisi

Aktif filtrelerin frekans yanıtı güvenli bir frekans ızgarasında taranarak maksimum pozitif kazanç hesaplanır. `Auto Headroom` açıkken preamp hedefi `manualPreamp - maxBoost - safetyMargin` olur ve mevcut smoothing ile uygulanır. Kullanıcı isterse manuel modu seçebilir.

Limiter gerçek kazanç çarpanını ve GR değerini (`20*log10(gain)`) snapshot’a yazar. Ceiling, lookahead ve release sabitleri tek konfigürasyon kaynağından gelir.

Kabul kriterleri: pozitif boost limiter’ı gereksiz zorlamaz; preamp geçişi klik üretmez; limiter GR UI’da 0 dB’den aşağı doğru gösterilir.

### Faz 2 — Profesyonel metering

L/R bağımsız peak ve 300 ms RMS, peak-hold, true-peak/headroom ve clipping göstergeleri eklenir. `LevelMeterView` mevcut basit peak çubuğunu koruyarak ayrıntılı görünümü `Measure` moduna taşır.

Kabul kriterleri: L/R ayrışması görünür; headroom negatif olduğunda CLIP uyarısı çıkar; ölçüm UI’si ses callback’ini bloke etmez.

### Faz 3 — Level-matched A/B ve hassas düzenleme

EQ aktif ve bypass yolları kısa RMS penceresinde ölçülerek çıkış kazancı eşlenir. A/B geçişi micro-crossfade ile yapılır. EQ parametreleri çift tıklama ile sayısal girilebilir; fare tekeri küçük adımlı düzenleme yapar.

Kabul kriterleri: A/B ses yüksekliği farkı pratikte duyulmayacak seviyeye iner; bypass limiter’ı devre dışı bırakmaz; geçişte pop/click yoktur.

### Faz 4 — Katmanlı kalibrasyon ve preset durumu

Kalibrasyon (AutoEQ/REW), hedef eğri ve oturum ayarı ayrı filtre katmanları olur. Preset’in değiştirilmiş durumu, undo/redo ve A/B/C snapshot yuvaları eklenir.

Kabul kriterleri: kalibrasyon katmanı yanlışlıkla ton ayarıyla ezilemez; preset kaydetmeden önce dirty durum görünür; eski preset formatları migrate edilir.

### Faz 5 — Sistem güvenliği, test ve dokümantasyon

Fiziksel cihaz ayrılması, CATap izin kaybı, aggregate device hatası ve uygulama kapanışı için güvenli fallback tamamlanır. DSP matematiği, limiter, metering, preset migration ve cihaz değişimi test edilir; README ve sistem-audio dokümanı gerçek davranışla hizalanır.

## Uygulama sırası

İlk kod iterasyonu Faz 0 ve Faz 1’in ölçüm/telemetri omurgasıdır. Sonraki her faz, önceki fazın kabul kriterleri geçmeden birleştirilmez.

