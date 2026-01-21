import 'dart:math';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
      title: 'AI Mutfak Asistanı',
      debugShowCheckedModeBanner: false,
      home: AiMutfak()
  ));
}

// --- PREMIUM TASARIM SİSTEMİ (Eksiksiz) ---
class AppStyle {
  static const Color anaRenk = Color(0xFFFF6F00);
  static const Color ikincilRenk = Color(0xFFFFB300);
  static const Color arkaPlan = Color(0xFFFDFDFD);
  static const LinearGradient turuncuGradyan = LinearGradient(
    colors: [Color(0xFFFF6F00), Color(0xFFFF9100)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const TextStyle baslikStili = TextStyle(fontFamily: 'Serif', fontWeight: FontWeight.w900, fontSize: 32, color: Colors.black87, letterSpacing: -0.5);
  static const TextStyle altBaslikStili = TextStyle(fontFamily: 'Sans-serif', fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black87);
  static const TextStyle metinStili = TextStyle(fontFamily: 'Sans-serif', fontSize: 16, height: 1.6, color: Color(0xFF424242));
}

class AiMutfak extends StatefulWidget {
  const AiMutfak({super.key});
  @override
  State<AiMutfak> createState() => _AiMutfakState();
}

class _AiMutfakState extends State<AiMutfak> with SingleTickerProviderStateMixin {
  // API ANAHTARLARI
  final String _geminiApiKey =dotenv.env['GEMINI_API_KEY'] ?? "";
  final String _groqApiKey = dotenv.env['GROQ_API_KEY'] ?? "";

  final TextEditingController _aramaController = TextEditingController();
  final Random _random = Random();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // TÜM DURUM DEĞİŞKENLERİ (Eksiksiz)
  bool _yukleniyor = false, _aciSever = false, _diyetModu = false, _vejetaryen = false, _yaraticiMod = false, _envanterModu = false;
  int _porsiyonSayisi = 4, _aktifSayfaIndex = 0;
  List<String> _favoriler = [], _sonBakilanlar = [];
  String _gununIpucu = "";

  @override
  void initState() {
    super.initState();
    _verileriYukle();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _pulseAnimation = Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  // --- KESİN DİL, KARAKTER VE MANTIK MOTORU ---
  String _promptOlustur(String? ot) {
    String a = ot ?? _aramaController.text;
    String dilKilidi = "DİL VE KARAKTER KURALI: Sadece TÜRKÇE konuş. Çince karakterler (汉字), Vietnamca harfler veya 'mixture', 'step', 'hỗn hợp' gibi kelimeleri ASLA kullanma. Karakterlerin tamamen Latin alfabesi olsun.";
    String vejetaryenFiltresi = _vejetaryen ? "MUTLAK KURAL: Bu tarif KESİNLİKLE VEJETARYEN olmalı. Et, tavuk, balık, et suyu YASAKTIR." : "";
    String modeDesc = _envanterModu
        ? "KURAL: SADECE şu malzemeleri kullanabilirsin: $a. Bunlara ek olarak sadece temel baharat/su/yağ ekle."
        : "İstek: $a.";

    List<String> tercihler = [];
    if (_aciSever) tercihler.add("Bol acılı ve baharatlı");
    if (_diyetModu) tercihler.add("Düşük kalorili ve sağlıklı");
    String tMetni = tercihler.isEmpty ? "Genel mutfak" : tercihler.join(", ");
    String sonHatirlatma = "\nÖNEMLİ: Eğer malzemeler gerçek bir yemeğe dönüşmüyorsa tarif verme, sadece HATA mesajı gönder.";

    return "Sen profesyonel bir Türk Şefisin. $dilKilidi MANTIK: Katı gıdalarda su bardağı kullanma. PORSIYON: $_porsiyonSayisi kişilik. $vejetaryenFiltresi $modeDesc TERCİHLER: $tMetni. Stil: ${_yaraticiMod ? 'Gurme' : 'Pratik'}. Format: YEMEK ADI\nMETADATA: Hazırlık | Pişirme | Zorluk | Kalori | Protein | Karb | Yağ\nMALZEMELER_BASLANGICI\n- M\nTARIF_BASLANGICI\n- A";

  }

// --- YEDEK MODEL (EKSİKTİ, EKLENDİ) ---
  // 1. ANA MODEL: Yüklemeyi açar ama asla kapatmaz (Boşluk olmaması için)
  Future<void> _tarifUret({String? otomatikMetin}) async {
    FocusScope.of(context).unfocus();
    String aramaMetni = (otomatikMetin ?? _aramaController.text).trim().toLowerCase();

    List<String> karaListe = ["zenci", "sünger", "goblin", "ejderha", "peri", "kedi", "mama", "taş", "kum", "plastik", "zehir", "sabun", "deterjan"];
    for (var kelime in karaListe) {
      if (aramaMetni.contains(kelime)) {
        _hataMesajiGoster("Şef Dursun! ✋ Mutfağımıza sadece gerçek malzemeler girebilir!");
        return;
      }
    }

    setState(() => _yukleniyor = true);
    try {
      final model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: _geminiApiKey,
        systemInstruction: Content.system("SEN BİR BİYOLOJİ VE MUTFAK DENETÇİSİSİN. Kesinlikle yaratıcı olma. Gerçek dünya mutfağından şaşma."),
        generationConfig: GenerationConfig(temperature: 0.0),
      );

      final response = await model.generateContent([Content.text(_promptOlustur(otomatikMetin))]);
      String taslakCevap = (response.text ?? "").trim();

      if (taslakCevap.contains("HATA") || taslakCevap.isEmpty) {
        setState(() => _yukleniyor = false);
        _hataMesajiGoster("Şef Dursun! ✋ Bu malzemelerle bir yemek bulunamadı.");
        return;
      }

      String yemekAdi = taslakCevap.split('\n')[0].trim();
      final checkResponse = await model.generateContent([
        Content.text("Soru: '$yemekAdi' adında gerçek bir insan yemeği var mı? Sadece EVET veya HAYIR yaz.")
      ]);

      if (checkResponse.text?.trim().toUpperCase().contains("HAYIR") ?? true) {
        setState(() => _yukleniyor = false);
        _hataMesajiGoster("Şef Dursun! ✋ '$yemekAdi' kurgusal bir yemektir.");
      } else {
        _veriyiIsleveGoster(taslakCevap);
      }
    } catch (e) {
      if (mounted) _groqYedek(otomatikMetin);
    }
  }

  // 2. YEDEK MODEL: Gemini hata verirse devreye girer
  Future<void> _groqYedek(String? ot) async {
    try {
      final resp = await http.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {'Authorization': 'Bearer $_groqApiKey', 'Content-Type': 'application/json'},
          body: jsonEncode({"model": "llama-3.3-70b-versatile", "messages": [{"role": "user", "content": _promptOlustur(ot)}]})
      );
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        _veriyiIsleveGoster(data['choices'][0]['message']['content']);
      } else {
        if (mounted) setState(() => _yukleniyor = false);
      }
    } catch (e) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  // 3. VERİ İŞLEME VE GEÇİŞ: Boşluğu silecek tek fonksiyon budur
  void _veriyiIsleveGoster(String m) async {
    // 1. MANTIK: YEMEK ADINI TÜM KIRLILIKLERDEN ARINDIRMA
    List<String> satirlar = m.trim().split('\n');
    String isim = "Nefis Tarif";

    if (satirlar.isNotEmpty) {
      // RegEx ile: ##, **, __ gibi Markdown işaretlerini ve "Yemek Adı:" gibi etiketleri siliyoruz
      isim = satirlar[0]
          .replaceAll(RegExp(r'[#*_]'), '') // İşaretleri sil
          .replaceAll(RegExp(r'^(Yemek Adı|Tarif|Yemek|Adı):\s*', caseSensitive: false), '') // Başlık eklerini sil
          .trim(); // Kalan boşlukları süpür
    }

    // 2. PREMİUM VERİ AYRIŞTIRMA (Eksiksiz)
    String meta = "25 dk | 40 dk | Orta | 400 | 20 | 45 | 15";
    for (var x in satirlar) {
      if (x.contains("METADATA:")) meta = x.replaceAll('METADATA:', '').trim();
    }

    var p = m.split('TARIF_BASLANGICI');
    if (p.length < 2) {
      if (mounted) setState(() => _yukleniyor = false);
      return;
    }
    String mal = p[0].split('MALZEMELER_BASLANGICI')[1].trim();
    String tar = p[1].trim();

    // 3. HAFIZAYA KAYDETME
    final prefs = await SharedPreferences.getInstance();
    String kayit = "$isim***$mal***$tar***$meta";
    _sonBakilanlar.removeWhere((item) => item.startsWith(isim));
    _sonBakilanlar.insert(0, kayit);
    if (_sonBakilanlar.length > 8) _sonBakilanlar.removeLast();
    await prefs.setStringList('sonBakilanlar', _sonBakilanlar);

    if (!mounted) return;

    // 4. SIFIR BOŞLUKLU GEÇİŞ (Videodaki sorunu bitiren await)
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (c) => TarifDetayEkrani(
          yemekAdi: isim, malzemeler: mal, tarif: tar, metaVerisi: meta, porsiyon: _porsiyonSayisi,
        )
    ));

    // 5. DÖNÜŞ KONTROLÜ
    if (mounted) {
      setState(() => _yukleniyor = false);
      _verileriYukle();
    }
  }
  void _verileriYukle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favoriler = prefs.getStringList('favoriler') ?? [];
      _sonBakilanlar = prefs.getStringList('sonBakilanlar') ?? [];
      _aciSever = prefs.getBool('aciSever') ?? false;
      _diyetModu = prefs.getBool('diyetModu') ?? false;
      _vejetaryen = prefs.getBool('vejetaryen') ?? false;
      _yaraticiMod = prefs.getBool('yaraticiMod') ?? false;
      _porsiyonSayisi = prefs.getInt('porsiyonSayisi') ?? 4;
      _ipucuGuncelle();
    });
  }

  void _ayarlariKaydet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('aciSever', _aciSever);
    await prefs.setBool('diyetModu', _diyetModu);
    await prefs.setBool('vejetaryen', _vejetaryen);
    await prefs.setBool('yaraticiMod', _yaraticiMod);
    await prefs.setInt('porsiyonSayisi', _porsiyonSayisi);
    _ipucuGuncelle();
  }

  void _ipucuGuncelle() {
    final l = _yaraticiMod ? ["👨‍🍳 Monter au beurre: Sosları tereyağı ile bağlayın.", "👨‍🍳 Baharatları mühürleyin."] : ["💡 Soğanları az tuzla kavurmak süreci hızlandırır.", "💡 Sebzeleri buzlu suya atın."];
    setState(() => _gununIpucu = l[_random.nextInt(l.length)]);
  }
  void _hataMesajiGoster(String mesaj) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)), // Yenilikçi yuvarlak köşeler
        title: const Row(
          children: [
            Icon(Icons.restaurant_menu, color: Colors.orange),
            SizedBox(width: 10),
            Text("Şefin Notu"),
          ],
        ),
        content: Text(mesaj, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Anladım Şefim", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _ayarlariAc() => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (c) => Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      padding: const EdgeInsets.all(24),
      child: StatefulBuilder(builder: (c, setM) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
        const SizedBox(height: 25),
        const Text("Mutfak Ayarları", style: AppStyle.altBaslikStili),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Porsiyon (Kişi Sayısı)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          Row(children: [
            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setM(() { if (_porsiyonSayisi > 1) _porsiyonSayisi--; _ayarlariKaydet(); })),
            Text("$_porsiyonSayisi", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setM(() { if (_porsiyonSayisi < 10) _porsiyonSayisi++; _ayarlariKaydet(); })),
          ]),
        ]),
        const Divider(),
        _switchTile("Yaratıcı Mod", Icons.auto_awesome, Colors.purple, _yaraticiMod, (v) => setM(() { _yaraticiMod = v; _ayarlariKaydet(); })),
        _switchTile("Acı Severim", Icons.whatshot, Colors.red, _aciSever, (v) => setM(() { _aciSever = v; _ayarlariKaydet(); })),
        _switchTile("Diyet Modu", Icons.eco, Colors.green, _diyetModu, (v) => setM(() { _diyetModu = v; _ayarlariKaydet(); })),
        _switchTile("Vejetaryen", Icons.grass, Colors.teal, _vejetaryen, (v) => setM(() { _vejetaryen = v; _ayarlariKaydet(); })),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: AppStyle.anaRenk, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text("KAYDET", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
      ]))));

  Widget _switchTile(String t, IconData i, Color c, bool v, Function(bool) onChanged) => SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t), secondary: Icon(i, color: c), value: v, activeColor: c, onChanged: onChanged);

  @override build(BuildContext context) => Scaffold(backgroundColor: AppStyle.arkaPlan, body: _aktifSayfaIndex == 0 ? _buildAnaSayfa() : _buildDefterim(), bottomNavigationBar: _buildNav());

  Widget _buildNav() => Container(decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)]), child: NavigationBar(backgroundColor: Colors.white, indicatorColor: AppStyle.anaRenk.withValues(alpha: 0.1), selectedIndex: _aktifSayfaIndex, onDestinationSelected: (i) => setState(() => _aktifSayfaIndex = i), destinations: const [NavigationDestination(icon: Icon(Icons.restaurant_menu_rounded), label: "Mutfak"), NavigationDestination(icon: Icon(Icons.auto_stories_rounded), label: "Defterim")]));

  Widget _buildAnaSayfa() => SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 70, 24, 30), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Selam Şefim! 👋", style: TextStyle(color: Colors.grey[600], fontSize: 16)), const Text("Ne Pişiriyoruz?", style: AppStyle.baslikStili)]),
      GestureDetector(onTap: _ayarlariAc, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]), child: Icon(_yaraticiMod ? Icons.auto_awesome : Icons.tune_rounded, color: _yaraticiMod ? Colors.purple : AppStyle.anaRenk))),
    ]),
    const SizedBox(height: 30),
    Row(children: [
      Expanded(child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 25, offset: const Offset(0, 10))]), child: TextField(controller: _aramaController, onSubmitted: (v) => _tarifUret(), decoration: InputDecoration(hintText: _envanterModu ? "Dolaptaki malzemeler..." : "Yemek veya malzeme...", prefixIcon: const Icon(Icons.search_rounded, color: AppStyle.anaRenk), border: InputBorder.none, contentPadding: const EdgeInsets.all(20))))),
      const SizedBox(width: 10),
      GestureDetector(onTap: () => setState(() => _envanterModu = !_envanterModu), child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: _envanterModu ? AppStyle.anaRenk : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppStyle.anaRenk)), child: Icon(Icons.kitchen_rounded, color: _envanterModu ? Colors.white : AppStyle.anaRenk))),
    ]),
    if (_yukleniyor) Center(child: Column(children: [const SizedBox(height: 50), FadeTransition(opacity: _pulseAnimation, child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppStyle.anaRenk.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.restaurant_menu_rounded, size: 60, color: AppStyle.anaRenk))), const SizedBox(height: 20), const Text("Şef Hazırlanıyor...")])) else ...[
      const SizedBox(height: 30),
      _buildChips(),
      const SizedBox(height: 35),
      const Text("Kategoriler", style: AppStyle.altBaslikStili),
      const SizedBox(height: 15),
      _buildGrid(),
      const SizedBox(height: 35),
      _buildTipCard(),
    ]
  ]));

  Widget _buildChips() => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: ["Makarna 🍝", "Kebap 🥩", "Tatlı 🍰", "Salata 🥗", "Diyet 🥗"].map((s) => Padding(padding: const EdgeInsets.only(right: 10), child: ActionChip(label: Text(s), backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), onPressed: () => _tarifUret(otomatikMetin: s)))).toList()));

  Widget _buildGrid() => GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.2, children: [
    _imgKat("Ana Yemek", "https://images.pexels.com/photos/262978/pexels-photo-262978.jpeg?auto=compress&w=600"),
    _imgKat("Tatlılar", "https://images.pexels.com/photos/1055272/pexels-photo-1055272.jpeg?auto=compress&w=600"),
    _imgKat("Kahvaltılık", "https://images.pexels.com/photos/103124/pexels-photo-103124.jpeg?auto=compress&w=600"),
    _imgKat("Deniz Ürünleri", "https://images.pexels.com/photos/262959/pexels-photo-262959.jpeg?auto=compress&w=600"),
    _imgKat("Hamur İşleri", "https://images.pexels.com/photos/2097090/pexels-photo-2097090.jpeg?auto=compress&w=600"),
    _imgKat("Fit Menü", "https://images.pexels.com/photos/1640777/pexels-photo-1640777.jpeg?auto=compress&w=600"),
  ]);

  Widget _imgKat(String t, String u) => GestureDetector(
    onTap: () => _tarifUret(otomatikMetin: t),
    child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20), // EKSTRA YUMUŞAK KÖŞELER
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5), // YENİLİKÇİ GÖLGE EFEKTİ
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Image.network(u, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ),
              // Hatalı olan: Alignment(0, 0.7, child: Text(...))
// Doğru olan:
              // 248. satır civarı - Kategori kartı metni hizalama
              Align(
                alignment: const Alignment(0, 0.7),
                child: Text(
                  t,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _buildTipCard() => Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFFFFF8E1), Colors.orange[50]!]), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.orange[100]!)), child: Row(children: [const Icon(Icons.lightbulb_rounded, color: AppStyle.anaRenk, size: 30), const SizedBox(width: 15), Expanded(child: Text(_gununIpucu, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.brown, fontSize: 15)))]));

  Widget _buildDefterim() => SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 70, 24, 30), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text("Defterim", style: AppStyle.baslikStili),
    const SizedBox(height: 30),
    if (_sonBakilanlar.isNotEmpty) ...[
      const Text("Son Baktıklarım", style: AppStyle.altBaslikStili),
      const SizedBox(height: 15),
      SizedBox(height: 140, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _sonBakilanlar.length, itemBuilder: (c, i) => _sonItem(_sonBakilanlar[i]))),
      const SizedBox(height: 35),
    ],
    const Text("Favorilerim", style: AppStyle.altBaslikStili),
    if (_favoriler.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(30), child: Text("Henüz favori tarifiniz yok.", style: TextStyle(color: Colors.grey)))) else ..._favoriler.map((f) => _favCard(f)).toList(),
  ]));

  Widget _sonItem(String f) {
    var p = f.split('***');
    return GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (c) => TarifDetayEkrani(yemekAdi: p[0], malzemeler: p[1], tarif: p[2], metaVerisi: p[3], porsiyon: 4))), child: Container(width: 160, margin: const EdgeInsets.only(right: 15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)], border: Border.all(color: Colors.grey[100]!)), child: Center(child: Padding(padding: const EdgeInsets.all(12), child: Text(p[0], textAlign: TextAlign.center, maxLines: 3, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppStyle.anaRenk))))));
  }

  Widget _favCard(String f) {
    var p = f.split('***');
    return Container(margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]), child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5), title: Text(p[0], style: const TextStyle(fontWeight: FontWeight.bold)), leading: const Icon(Icons.bookmark_rounded, color: AppStyle.anaRenk), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (c) => TarifDetayEkrani(yemekAdi: p[0], malzemeler: p[1], tarif: p[2], metaVerisi: p[3], porsiyon: 4)))));
  }

  @override void dispose() { _pulseController.dispose(); _aramaController.dispose(); super.dispose(); }
}

class TarifDetayEkrani extends StatefulWidget {
  final String yemekAdi, malzemeler, tarif, metaVerisi;
  final int porsiyon;
  const TarifDetayEkrani({super.key, required this.yemekAdi, required this.malzemeler, required this.tarif, required this.metaVerisi, required this.porsiyon});
  @override State<TarifDetayEkrani> createState() => _TarifDetayEkraniState();
}

class _TarifDetayEkraniState extends State<TarifDetayEkrani> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _timer;
  int _kalanSaniye = 0;
  bool _sayacAktif = false, _isFavorited = false;
  List<bool> _adimlarTamamlandi = [];

  @override void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _adimlarTamamlandi = List.generate(widget.tarif.split('\n').where((s)=>s.isNotEmpty).length, (index) => false);
    _favoriKontrol();
  }

  @override void dispose() { _timer?.cancel(); _tabController.dispose(); super.dispose(); }

  Future<void> _favoriKontrol() async { final prefs = await SharedPreferences.getInstance(); List<String> list = prefs.getStringList('favoriler') ?? []; setState(() => _isFavorited = list.any((f) => f.startsWith(widget.yemekAdi))); }
  Future<void> _toggleFavori() async { final prefs = await SharedPreferences.getInstance(); List<String> list = prefs.getStringList('favoriler') ?? []; String v = "${widget.yemekAdi}***${widget.malzemeler}***${widget.tarif}***${widget.metaVerisi}"; if (_isFavorited) { list.removeWhere((f) => f.startsWith(widget.yemekAdi)); } else { list.add(v); } await prefs.setStringList('favoriler', list); setState(() => _isFavorited = !_isFavorited); }

  void _sayacBaslat(int dak) {
    _timer?.cancel();
    setState(() { _kalanSaniye = dak * 60; _sayacAktif = true; });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) { if (_kalanSaniye > 0 && mounted) setState(() => _kalanSaniye--); else { _timer?.cancel(); if (mounted) setState(() => _sayacAktif = false); } });
  }

  double get _ilerleme => _adimlarTamamlandi.isEmpty ? 0 : _adimlarTamamlandi.where((t) => t).length / _adimlarTamamlandi.length;

  @override Widget build(BuildContext context) {
    List<String> meta = widget.metaVerisi.split('|');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, title: Text(widget.yemekAdi, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), leading: const BackButton(color: Colors.black),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect( // Çubuğun uçlarını yuvarlar
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _ilerleme,
                  backgroundColor: Colors.orange[50],
                  color: AppStyle.anaRenk,
                  minHeight: 6,
                ),
              ),
            ),
          ),
          actions: [IconButton(icon: Icon(_isFavorited ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: AppStyle.anaRenk), onPressed: _toggleFavori), IconButton(icon: const Icon(Icons.ios_share_rounded, color: Colors.black), onPressed: () => Share.share("Chef'ten Tarif: ${widget.yemekAdi}\n\n${widget.tarif}"))]),
      body: Stack(children: [
        Column(children: [
          Container(margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: AppStyle.anaRenk.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.people_alt_rounded, size: 20, color: AppStyle.anaRenk), const SizedBox(width: 10), Text("${widget.porsiyon} Kişilik Özel Ölçüler", style: const TextStyle(fontWeight: FontWeight.bold, color: AppStyle.anaRenk))])),
          TabBar(controller: _tabController, labelColor: AppStyle.anaRenk, unselectedLabelColor: Colors.grey, indicatorColor: AppStyle.anaRenk, indicatorWeight: 3, tabs: const [Tab(text: "Malzemeler"), Tab(text: "Yapılışı"), Tab(text: "Besin")]),
          Expanded(child: TabBarView(controller: _tabController, children: [_malzemeSekmesi(widget.malzemeler), _yapilisSekmesi(widget.tarif), _besinSekmesi(meta)]))
        ]),
        if (_ilerleme == 1.0) _kutlamaPaneli(),
        if (_sayacAktif) Align(alignment: Alignment.bottomCenter, child: _timerPanel()),
      ]),
    );
  }

  Widget _timerPanel() => Container(margin: const EdgeInsets.all(24), padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 18), decoration: BoxDecoration(gradient: AppStyle.turuncuGradyan, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: AppStyle.anaRenk.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))]), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.timer_outlined, color: Colors.white, size: 28), const SizedBox(width: 15), Text("${_kalanSaniye ~/ 60}:${(_kalanSaniye % 60).toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)), const SizedBox(width: 15), IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70), onPressed: () => setState(() => _sayacAktif = false))]));

  Widget _malzemeSekmesi(String v) => ListView(padding: const EdgeInsets.all(24), children: v.split('\n').where((s)=>s.isNotEmpty).map((s) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[100]!)), child: Row(children: [const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20), const SizedBox(width: 12), Expanded(child: Text(s.trim(), style: AppStyle.metinStili))]))).toList());

  Widget _yapilisSekmesi(String v) {
    var adimlar = v.split('\n').where((s)=>s.isNotEmpty).toList();
    return ListView.builder(itemCount: adimlar.length, padding: const EdgeInsets.fromLTRB(24, 24, 24, 100), itemBuilder: (c, i) {
      final match = RegExp(r'(\d+)\s*dakika').firstMatch(adimlar[i].toLowerCase());
      bool pisirme = adimlar[i].toLowerCase().contains("pişir") || adimlar[i].toLowerCase().contains("fırın") || adimlar[i].toLowerCase().contains("kaynat") || adimlar[i].toLowerCase().contains("sotele");
      return GestureDetector(onTap: () => setState(() => _adimlarTamamlandi[i] = !_adimlarTamamlandi[i]), child: Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: _adimlarTamamlandi[i] ? Colors.orange[50] : Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)], border: Border.all(color: Colors.grey[100]!)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(backgroundColor: _adimlarTamamlandi[i] ? Colors.green : AppStyle.anaRenk, child: Text("${i + 1}", style: const TextStyle(color: Colors.white))),
          const SizedBox(width: 15),
          Expanded(child: Text(adimlar[i], style: TextStyle(decoration: _adimlarTamamlandi[i] ? TextDecoration.lineThrough : null, color: _adimlarTamamlandi[i] ? Colors.grey : Colors.black87))),
        ]),
        if (match != null && pisirme) Padding(padding: const EdgeInsets.only(top: 15), child: ElevatedButton.icon(onPressed: () => _sayacBaslat(int.parse(match.group(1)!)), icon: const Icon(Icons.timer_outlined, size: 18), label: const Text("SAYACI BAŞLAT"), style: ElevatedButton.styleFrom(backgroundColor: AppStyle.anaRenk, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))))
      ])));
    });
  }

  Widget _besinSekmesi(List<String> m) => Padding(padding: const EdgeInsets.all(24), child: Column(children: [_besinKarti("Kalori", "${m.length > 3 ? m[3] : '--'} kcal", Colors.orange), const SizedBox(height: 15), Row(children: [Expanded(child: _besinKarti("Protein", "${m.length > 4 ? m[4] : '--'}g", Colors.blue)), const SizedBox(width: 15), Expanded(child: _besinKarti("Karb", "${m.length > 5 ? m[5] : '--'}g", Colors.green))]), const SizedBox(height: 15), _besinKarti("Yağ", "${m.length > 6 ? m[6] : '--'}g", Colors.red)]));

  Widget _besinKarti(String t, String v, Color c) => Container(padding: const EdgeInsets.all(20), width: double.infinity, decoration: BoxDecoration(color: c.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: 0.1))), child: Column(children: [Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(height: 5), Text(v, style: TextStyle(color: c, fontSize: 26, fontWeight: FontWeight.w900))]));
  Widget _kutlamaPaneli() => Container(color: Colors.white.withValues(alpha: 0.9), child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.stars_rounded, color: Colors.orange, size: 100), Text("AFİYET OLSUN ŞEFİM!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))])));
}