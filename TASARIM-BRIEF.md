# Alışveriş Listem — Tasarım Prompt'u

Aşağıdaki metni bir tasarım aracına (Figma AI, v0, Galileo, Uizard, ChatGPT/Claude
görsel modu vb.) yapıştır. Mevcut tasarımı taklit etmesi gerekmiyor — proje tanımı
ve ekran listesi sabit, görsel dil tamamen tasarıma bırakılmıştır.

---

## Proje tanımı

**Alışveriş Listem**, paylaşımlı bir alışveriş listesi mobil uygulamasıdır.
Kullanıcı listeler oluşturur, her listeye ürün ekler (kategori, adet ve market
bilgisiyle) ve alışveriş sırasında ürünleri tamamlandıkça işaretler.

Uygulamanın üç ek katmanı var:
- **Sosyal:** Kullanıcı e-posta ile arkadaş ekler, bir listeyi bir arkadaşıyla
  paylaşır; iki taraf da aynı listeyi eş zamanlı düzenleyebilir, değişikliklerde
  karşı tarafa bildirim gider.
- **Yapay zeka:** Bir sohbet asistanı (ne alınmalı, eldeki malzemeyle tarif,
  stok/eksik takibi gibi sorulara yardım eder).
- **İstatistik:** Tamamlanma oranı, kategori dağılımı, zaman içindeki alışveriş
  ritmi, en sık alınan ürünler.

**Kullanıcı profili:** Genel kullanıcı; ev/aile alışverişini düzenlemek isteyen
kişiler. **Ton:** Sade, hızlı, güven veren; market işini kolaylaştıran pratik bir
yardımcı. **Platform:** Mobil öncelikli (dikey telefon); açık ve koyu tema
desteklenmeli.

## Ekranlar (bu liste sabit)

1. **Giriş / Kayıt** — E-posta + şifre ile giriş ve kayıt; şifre sıfırlama.
2. **Ana Sayfa** — Genel bakış ve hızlı giriş noktası: kullanıcının listeleri,
   bekleyen ürün/aktif liste özeti, kategoriler, kısa istatistik ve öneriler.
   Yeni kullanıcıya karşılama/onboarding.
3. **Listelerim** — Kullanıcının kendi listeleri + kendisiyle paylaşılan listeler
   bir arada; her listede ad, ürün sayısı, tamamlanma durumu, paylaşım bilgisi.
4. **Liste Oluştur** — Liste adı ve ilk ürünlerin girişi (ürün adı, kategori,
   adet, market); hazır şablonlar opsiyonel.
5. **Liste Detayı** — Asıl çalışma ekranı: ürünleri görüntüleme, ekleme,
   düzenleme, tamamlandı olarak işaretleme; kategoriye göre filtre;
   tamamlananları gizleme; listeyi kişiyle paylaşma; tamamlanma göstergesi.
6. **İstatistikler** — Tamamlanma oranı, kategori dağılımı (pasta), aylık/haftalık
   alışveriş ritmi (bar/çizgi), en çok alınan ürünler; zaman aralığı seçimi.
7. **AI Sohbet** — Asistanla mesajlaşma; ilk açılışta örnek sorular; asistanın
   önerdiği ürünleri listeye ekleyebilme.
8. **Profil** — Avatar (fotoğraf yükleme), düzenlenebilir ad, e-posta; arkadaşlar,
   bildirimler, ayarlar, yardım ve çıkış kısayolları.
9. **Ayarlar** — Tema (sistem/açık/koyu), dil, şifre sıfırlama, uygulama hakkında.
10. **Arkadaşlar** — Üç bölüm: mevcut arkadaşlar, gelen istekler, gönderilen
    istekler; e-posta ile arkadaş ekleme; her satırda avatar, isim, e-posta.
11. **Bildirimler** — Paylaşım, arkadaşlık ve liste güncellemesi bildirimleri;
    okundu durumu; bildirime dokununca ilgili ekrana gitme.
12. **Kategori Detayı** — Tek bir kategoriye ait geçmiş: o kategoride en çok
    alınan ürünler, son alım tarihleri, o kategoriden hızlı ekleme.

## İstenen çıktı

Yukarıdaki 12 ekranın her biri için mobil mockup üret. Her ekranın hem **açık**
hem **koyu** temasını, ayrıca liste/grid içeren ekranlarda **boş durum** ile
**dolu durum** varyantlarını ver. Alt gezinme, ana eylem butonu, tipografi, renk
paleti, ikon stili ve bileşen tasarımı sana bırakılmıştır; tutarlı ve modern bir
tasarım sistemi kur ve kullandığın renk/ölçü kararlarını kısa notlarla belirt.
