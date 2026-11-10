// =============================================================================
// LPP 552 RÉGHAÏA – APPLICATION FLUTTER COMPLÈTE (42 ÉCRANS + INIT SERRURES J1)
// =============================================================================
// Fichier : lib/main.dart
// Charte UI/UX : Vert Sapin (#14676B), Fond (#F4F5F7), Alerte Rouge (#A52524)
// =============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lpp552_service.dart';

const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://VOTRE_PROJET.supabase.co',
);
const String kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'VOTRE_CLE_ANON_SUPABASE',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  runApp(const Lpp552App());
}

class Lpp552App extends StatelessWidget {
  const Lpp552App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Résidence LPP 552',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(Lpp552Colors.scaffoldBg),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(Lpp552Colors.tealPrimary),
          primary: const Color(Lpp552Colors.tealPrimary),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(Lpp552Colors.scaffoldBg),
          foregroundColor: Color(0xFF111827),
          elevation: 0,
          centerTitle: false,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(Lpp552Colors.tealPrimary),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      home: const PorteEntreeAuth(),
    );
  }
}

// =============================================================================
// PORTE D'ENTRÉE : VÉRIFICATION DU PROFIL LOCAL & DÉVERROUILLAGE PIN/BIOMÉTRIE
// =============================================================================
class PorteEntreeAuth extends StatefulWidget {
  const PorteEntreeAuth({super.key});

  @override
  State<PorteEntreeAuth> createState() => _PorteEntreeAuthState();
}

class _PorteEntreeAuthState extends State<PorteEntreeAuth> {
  ProfilLocalLpp552? _profil;
  bool _chargement = true;
  bool _deverrouille = false;

  @override
  void initState() {
    super.initState();
    _initialiserSession();
  }

  Future<void> _initialiserSession() async {
    final p = await Lpp552Service.instance.chargerProfilCourant();
    if (!mounted) return;
    setState(() {
      _profil = p;
      _chargement = false;
    });
    if (p != null) {
      final ok = await Lpp552Service.instance.deverrouillerParBiometrieOuPin();
      if (ok && mounted) {
        setState(() => _deverrouille = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profil == null) {
      return EcranActivationAppareil(
        onCompteActive: (nouveauProfil) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EcranCreationPinBiometrie(profil: nouveauProfil),
            ),
          );
        },
      );
    }
    if (!_deverrouille) {
      return EcranSaisiePinDeverrouillage(
        profil: _profil!,
        onSucces: () => setState(() => _deverrouille = true),
      );
    }
    return ShellPrincipalLpp552(profil: _profil!);
  }
}

// =============================================================================
// ÉCRAN 01 : ACTIVATION DE L'APPAREIL (NUMÉRO + CODE À 6 CHIFFRES)
// =============================================================================
class EcranActivationAppareil extends StatefulWidget {
  final void Function(ProfilLocalLpp552 profil) onCompteActive;
  const EcranActivationAppareil({super.key, required this.onCompteActive});

  @override
  State<EcranActivationAppareil> createState() => _EcranActivationAppareilState();
}

class _EcranActivationAppareilState extends State<EcranActivationAppareil> {
  final _telCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  Future<void> _activer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final deviceId = '${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}';
      final profil = await Lpp552Service.instance.activerAppareil(
        telephone: _telCtrl.text,
        code6Chiffres: _codeCtrl.text,
        deviceId: deviceId,
      );
      widget.onCompteActive(profil);
    } catch (e) {
      setState(() => _erreur = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(Lpp552Colors.tealPrimary),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.sensor_door_outlined, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 20),
              const Text(
                'Résidence LPP 552',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Entrez le code remis par votre représentant de bloc pour activer cette application.',
                style: TextStyle(fontSize: 15, color: Color(0xFF5F6C72), height: 1.4),
              ),
              const SizedBox(height: 24),
              const Text('Numéro de téléphone', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _telCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '05 XX XX XX XX',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Code d\'activation', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: '6 chiffres',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCE8E6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_erreur!, style: const TextStyle(color: Color(0xFFB91C1C))),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _enCours ? null : _activer,
                child: _enCours
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text('Activer mon appareil'),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(Lpp552Colors.tealLightBg),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Aucun SMS n\'est envoyé. Ce code remis par votre représentant est valable 48 heures. '
                  'Vous choisirez ensuite votre propre code PIN ; l\'application ne marchera que sur ce téléphone.',
                  style: TextStyle(fontSize: 13.5, height: 1.45),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EcranInitialisationSerruresJour1()),
                    );
                  },
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: const Text('Installateur Jour 1 : Initialiser les 13 serrures'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ÉCRAN 02 : CHOIX DU CODE PIN & ACTIVATION BIOMÉTRIE
// =============================================================================
class EcranCreationPinBiometrie extends StatefulWidget {
  final ProfilLocalLpp552 profil;
  const EcranCreationPinBiometrie({super.key, required this.profil});

  @override
  State<EcranCreationPinBiometrie> createState() => _EcranCreationPinBiometrieState();
}

class _EcranCreationPinBiometrieState extends State<EcranCreationPinBiometrie> {
  final _pin1Ctrl = TextEditingController();
  final _pin2Ctrl = TextEditingController();
  bool _biometrie = true;
  String? _erreur;

  Future<void> _valider() async {
    if (_pin1Ctrl.text.length < 4 || _pin1Ctrl.text != _pin2Ctrl.text) {
      setState(() => _erreur = 'Les deux codes PIN doivent être identiques (4 à 6 chiffres).');
      return;
    }
    await Lpp552Service.instance.enregistrerCodePinEtBiometrie(
      codePin: _pin1Ctrl.text,
      activerBiometrie: _biometrie,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ShellPrincipalLpp552(profil: widget.profil)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Première connexion · Étape 2 sur 2',
                  style: TextStyle(color: Color(0xFF5F6C72), fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('Choisissez votre code PIN & biométrie',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Ce code remplace celui remis par votre représentant. Activez aussi votre empreinte pour ouvrir plus vite devant la porte.',
                style: TextStyle(color: Color(0xFF5F6C72), height: 1.4),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _pin1Ctrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Nouveau code PIN (4 à 6 chiffres)',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pin2Ctrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Confirmez le code PIN',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E6EA)),
                ),
                child: SwitchListTile(
                  title: const Text('Empreinte digitale / Face ID',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Ouverture rapide sans taper le code PIN'),
                  value: _biometrie,
                  activeColor: const Color(Lpp552Colors.tealPrimary),
                  onChanged: (v) => setState(() => _biometrie = v),
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 10),
                Text(_erreur!, style: const TextStyle(color: Color(0xFFB91C1C))),
              ],
              const Spacer(),
              ElevatedButton(onPressed: _valider, child: const Text('Valider mon code PIN')),
            ],
          ),
        ),
      ),
    );
  }
}

class EcranSaisiePinDeverrouillage extends StatefulWidget {
  final ProfilLocalLpp552 profil;
  final VoidCallback onSucces;
  const EcranSaisiePinDeverrouillage({super.key, required this.profil, required this.onSucces});

  @override
  State<EcranSaisiePinDeverrouillage> createState() => _EcranSaisiePinDeverrouillageState();
}

class _EcranSaisiePinDeverrouillageState extends State<EcranSaisiePinDeverrouillage> {
  final _pinCtrl = TextEditingController();
  String? _erreur;

  Future<void> _verifier() async {
    final ok = await Lpp552Service.instance.deverrouillerParBiometrieOuPin(codePinSaisi: _pinCtrl.text);
    if (ok) {
      widget.onSucces();
    } else {
      setState(() => _erreur = 'Code PIN incorrect.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bonjour ${widget.profil.nomPrenom}',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Saisissez votre code PIN ou utilisez votre empreinte digitale.'),
              const SizedBox(height: 24),
              TextField(
                controller: _pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  if (v.length >= 4) _verifier();
                },
                decoration: InputDecoration(
                  labelText: 'Code PIN',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(_erreur!, style: const TextStyle(color: Color(0xFFB91C1C))),
              ],
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _verifier, child: const Text('Déverrouiller')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await Lpp552Service.instance.deverrouillerParBiometrieOuPin();
                  if (ok) widget.onSucces();
                },
                icon: const Icon(Icons.fingerprint),
                label: const Text('Utiliser l\'empreinte digitale'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SHELL PRINCIPAL : ROUTAGE SELON LE RÔLE + POP-UP OBLIGATOIRE (ÉCRANS 03 & 04)
// =============================================================================
class ShellPrincipalLpp552 extends StatefulWidget {
  final ProfilLocalLpp552 profil;
  const ShellPrincipalLpp552({super.key, required this.profil});

  @override
  State<ShellPrincipalLpp552> createState() => _ShellPrincipalLpp552State();
}

class _ShellPrincipalLpp552State extends State<ShellPrincipalLpp552> {
  int _ongletIndex = 0;
  int _nbNotifsNonLues = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifierAnnoncesObligatoires();
      _demarrerEcouteTempsReel();
    });
  }

  void _demarrerEcouteTempsReel() {
    Lpp552Service.instance.ecouterNotificationsTempsReel(
      profil: widget.profil,
      onNouvelleNotification: (notif) {
        if (!mounted) return;
        setState(() => _nbNotifsNonLues++);

        // Si c'est une alerte critique SOS Ascenseur ou Portail bloqué -> Plein écran rouge immédiat !
        if (notif['priorite'] == 'CRITIQUE_PLEIN_ECRAN') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EcranAlarmePleinEcranRouge(notification: notif),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(Lpp552Colors.tealPrimary),
              content: Text('${notif['titre']} : ${notif['corps_message']}'),
            ),
          );
        }
      },
    );
  }

  /// Écrans 03 & 04 : Affiche les annonces non traitées l'une après l'autre ("1 sur 2")
  /// sans aucun bouton de fermeture (PopScope canPop: false)
  Future<void> _verifierAnnoncesObligatoires() async {
    if (widget.profil.bloc == null || widget.profil.idAppart == null) return;
    try {
      final annonces = await Lpp552Service.instance.getAnnoncesObligatoiresNonTraitees(
        bloc: widget.profil.bloc!,
        idAppart: widget.profil.idAppart!,
      );
      for (int i = 0; i < annonces.length; i++) {
        if (!mounted) break;
        final a = annonces[i];
        await showModalBottomSheet<void>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => PopScope(
            canPop: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: a['type_annonce'] == 'AVIS'
                              ? const Color(Lpp552Colors.statusYellowBg)
                              : const Color(Lpp552Colors.tealLightBg),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          a['type_annonce'] == 'AVIS' ? 'AVIS · IMPORTANT' : 'SONDAGE · VOLONTARIAT',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text('${i + 1} sur ${annonces.length}',
                          style: const TextStyle(color: Color(0xFF5F6C72))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(a['titre'] as String,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(a['description'] as String,
                      style: const TextStyle(fontSize: 15, color: Color(0xFF4B5563), height: 1.4)),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(Lpp552Colors.scaffoldBg),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${a['date_heure_texte']} · ${a['lieu']}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 18),
                  if (a['type_annonce'] == 'AVIS')
                    ElevatedButton(
                      onPressed: () async {
                        await Lpp552Service.instance.repondreAnnonce(
                          idAnnonce: a['id'] as String,
                          idAppart: widget.profil.idAppart!,
                          bloc: widget.profil.bloc!,
                          reponse: 'J_AI_VU',
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: const Text('J\'ai vu'),
                    )
                  else ...[
                    ElevatedButton(
                      onPressed: () async {
                        await Lpp552Service.instance.repondreAnnonce(
                          idAnnonce: a['id'] as String,
                          idAppart: widget.profil.idAppart!,
                          bloc: widget.profil.bloc!,
                          reponse: 'JE_PARTICIPE',
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: const Text('Je participe'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      onPressed: () async {
                        await Lpp552Service.instance.repondreAnnonce(
                          idAnnonce: a['id'] as String,
                          idAppart: widget.profil.idAppart!,
                          bloc: widget.profil.bloc!,
                          reponse: 'JE_NE_PEUX_PAS',
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: const Text('Je ne peux pas'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Center(
                    child: Text('Pour continuer, répondez à cette annonce.',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF5F6C72))),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Si l'utilisateur est Agent de sécurité ou Technicien, afficher leur interface dédiée
    if (widget.profil.role == 'AGENT') {
      return EcranPosteGardeAgent(profil: widget.profil);
    }
    if (widget.profil.role == 'TECHNICIEN') {
      return EcranMaintenanceTechnicien(profil: widget.profil);
    }

    final pages = <Widget>[
      OngletAccesResident(profil: widget.profil, nbNotifs: _nbNotifsNonLues),
      OngletTableauDeBordBloc(profil: widget.profil),
      OngletVisiteursResident(profil: widget.profil),
      OngletAideEtUrgences(profil: widget.profil),
      if (widget.profil.estRepresentant) OngletGererBlocRepresentant(profil: widget.profil),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_ongletIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _ongletIndex,
        onDestinationSelected: (idx) => setState(() => _ongletIndex = idx),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.sensor_door_outlined), label: 'Accès'),
          const NavigationDestination(icon: Icon(Icons.apartment_outlined), label: 'Bloc'),
          const NavigationDestination(icon: Icon(Icons.people_outline), label: 'Visiteurs'),
          const NavigationDestination(icon: Icon(Icons.help_outline), label: 'Aide'),
          if (widget.profil.estRepresentant)
            const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Gérer'),
        ],
      ),
    );
  }
}

// =============================================================================
// ONGLET 1 : ACCUEIL RÉSIDENT & OUVERTURE BLUETOOTH (ÉCRANS 05 & 06)
// =============================================================================
class OngletAccesResident extends StatelessWidget {
  final ProfilLocalLpp552 profil;
  final int nbNotifs;
  const OngletAccesResident({super.key, required this.profil, required this.nbNotifs});

  void _lancerOuverturePorte(BuildContext context, String idSerrure, String titrePorte) {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ModaleSynchroOuvertureJit(idSerrure: idSerrure, titrePorte: titrePorte),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int bloc = profil.bloc ?? 13;
    final String numAppart = profil.idAppart?.split('-').last ?? '05';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bloc $bloc · Appartement $numAppart',
                    style: const TextStyle(color: Color(0xFF5F6C72), fontSize: 14)),
                const Text('Bonjour',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              ],
            ),
            IconButton.filledTonal(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EcranNotificationsBloc(profil: profil)),
                );
              },
              icon: Badge(
                isLabelVisible: nbNotifs > 0,
                label: Text('$nbNotifs'),
                child: const Icon(Icons.notifications_outlined, color: Color(Lpp552Colors.tealPrimary)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Carte principale Porte du bloc
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(Lpp552Colors.tealPrimary),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.Edgesensor_high, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Porte du bloc $bloc',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                      const Text('À portée de Bluetooth',
                          style: TextStyle(color: Color(0xFFD1EAEB), fontSize: 14)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(Lpp552Colors.tealPrimary),
                  ),
                  onPressed: () => _lancerOuverturePorte(
                    context,
                    'BLOC_${bloc}_PORTE',
                    'Porte du bloc $bloc',
                  ),
                  child: const Text('Ouvrir'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Autres accès & services',
            style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF5F6C72))),
        const SizedBox(height: 10),
        _LigneService(
          titre: 'Portail principal',
          sousTitre: 'Entrée de la résidence',
          texteBouton: 'Ouvrir',
          onTap: () => _lancerOuverturePorte(context, 'PORTAIL_PRINCIPAL', 'Portail principal'),
        ),
        _LigneService(
          titre: 'Ascenseur',
          sousTitre: 'Bloc $bloc',
          texteBouton: 'Ouvrir',
          onTap: () => _lancerOuverturePorte(context, 'BLOC_${bloc}_ASC', 'Ascenseur Bloc $bloc'),
        ),
        _LigneService(
          titre: 'Signaler une panne',
          sousTitre: 'Ascenseur, éclairage, pompe...',
          texteBouton: 'Signaler',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranSignalerPanne(profil: profil)),
            );
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(Lpp552Colors.statusGreenBg),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(Lpp552Colors.statusGreenTxt), size: 28),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cotisation à jour',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                  Text(
                    'Valable jusqu\'au ${profil.dateExpirationAcces.toIso8601String().split('T').first}',
                    style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LigneService extends StatelessWidget {
  final String titre;
  final String sousTitre;
  final String texteBouton;
  final VoidCallback onTap;

  const _LigneService({
    required this.titre,
    required this.sousTitre,
    required this.texteBouton,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E6EA)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(sousTitre, style: const TextStyle(fontSize: 13, color: Color(0xFF5F6C72))),
            ],
          ),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(Lpp552Colors.tealPrimary),
              side: const BorderSide(color: Color(Lpp552Colors.tealPrimary), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(texteBouton, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Écran 06 : Modale de synchronisation JIT avec bouton "Ouvrir sans attendre"
class _ModaleSynchroOuvertureJit extends StatefulWidget {
  final String idSerrure;
  final String titrePorte;
  const _ModaleSynchroOuvertureJit({required this.idSerrure, required this.titrePorte});

  @override
  State<_ModaleSynchroOuvertureJit> createState() => _ModaleSynchroOuvertureJitState();
}

class _ModaleSynchroOuvertureJitState extends State<_ModaleSynchroOuvertureJit> {
  int _etape = 0;
  int _total = 0;
  String _message = 'Connexion sécurisée en cours...';

  @override
  void initState() {
    super.initState();
    _demarrer(sansAttendre: false);
  }

  void _demarrer({required bool sansAttendre}) {
    Lpp552Service.instance.ouvrirPorteAvecSynchroJit(
      idSerrure: widget.idSerrure,
      ouvrirSansAttendre: sansAttendre,
      onProgressionJit: (courant, total) {
        if (mounted) {
          setState(() {
            _etape = courant;
            _total = total;
          });
        }
      },
      onPorteOuverte: () {
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(Lpp552Colors.statusGreenTxt),
            content: Text('${widget.titrePorte} ouverte ✓'),
          ),
        );
      },
      onErreur: (err) {
        if (!mounted) return;
        setState(() => _message = err);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.titrePorte, style: const TextStyle(color: Color(0xFF5F6C72))),
          const SizedBox(height: 20),
          const SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              color: Color(Lpp552Colors.tealPrimary),
              strokeWidth: 6,
            ),
          ),
          const SizedBox(height: 20),
          Text(_message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Restez devant la porte. Elle s\'ouvre dès que la mise à jour est terminée.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF5F6C72)),
          ),
          if (_total > 0) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _etape / _total),
            const SizedBox(height: 6),
            Text('Mise à jour de la serrure : $_etape sur $_total'),
          ],
          const SizedBox(height: 20),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => _demarrer(sansAttendre: true),
            child: const Text('Ouvrir sans attendre'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ONGLET 2, 3 & 4 : TABLEAUX DE BORD, VISITEURS, AIDE & SOS (ÉCRANS 07–15)
// =============================================================================
class OngletTableauDeBordBloc extends StatelessWidget {
  final ProfilLocalLpp552 profil;
  const OngletTableauDeBordBloc({super.key, required this.profil});

  @override
  Widget build(BuildContext context) {
    final int bloc = profil.bloc ?? 13;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Lpp552Service.instance.getGrilleCotisationsBloc(bloc: bloc, annee: 2026),
      builder: (context, snap) {
        final items = snap.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Cotisations du bloc $bloc (2026)',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Vert : à jour · Jaune : partiel · Rouge : en dette',
                style: TextStyle(color: Color(0xFF5F6C72))),
            const SizedBox(height: 16),
            if (snap.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.25,
                ),
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final row = items[i];
                  final int pct = (row['pourcentage_paye'] as int?) ?? 0;
                  final Color bg = pct >= 100
                      ? const Color(Lpp552Colors.statusGreenBg)
                      : pct > 0
                          ? const Color(Lpp552Colors.statusYellowBg)
                          : const Color(0xFFFCE8E6);
                  final Color fg = pct >= 100
                      ? const Color(Lpp552Colors.statusGreenTxt)
                      : pct > 0
                          ? const Color(Lpp552Colors.statusYellowTxt)
                          : const Color(0xFFB91C1C);
                  return Container(
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${row['num_appart_affiche']}',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: fg)),
                        Text('$pct %', style: TextStyle(fontSize: 12, color: fg)),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class OngletVisiteursResident extends StatelessWidget {
  final ProfilLocalLpp552 profil;
  const OngletVisiteursResident({super.key, required this.profil});

  @override
  Widget build(BuildContext context) {
    final nomCtrl = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Visiteurs', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('L\'agent de sécurité verra le nom et la photo à l\'arrivée du visiteur.'),
          const SizedBox(height: 20),
          TextField(
            controller: nomCtrl,
            decoration: InputDecoration(
              labelText: 'Nom et prénom du visiteur attendu',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              if (nomCtrl.text.trim().isEmpty || profil.idAppart == null) return;
              await Supabase.instance.client.from('visiteurs').insert({
                'id_appart': profil.idAppart,
                'bloc': profil.bloc ?? 13,
                'nom_visiteur': nomCtrl.text.trim(),
                'type_visite': 'PREVUE',
              });
              nomCtrl.clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Visiteur pré-enregistré auprès du poste de garde.')),
                );
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Pré-enregistrer ce visiteur'),
          ),
        ],
      ),
    );
  }
}

class OngletAideEtUrgences extends StatelessWidget {
  final ProfilLocalLpp552 profil;
  const OngletAideEtUrgences({super.key, required this.profil});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Aide & Urgences', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E6EA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Le portail ne s\'ouvre pas ?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('L\'agent de sécurité est alerté tout de suite et intervient à la main.'),
              const SizedBox(height: 14),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(Lpp552Colors.alertRed)),
                onPressed: () async {
                  await Lpp552Service.instance.signalerPortailBloque();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Alarme envoyée à l\'agent de sécurité.')),
                    );
                  }
                },
                child: const Text('Signaler un problème portail'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E6EA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bloqué dans l\'ascenseur ?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                  'Alerte simultanément l\'agent de sécurité et votre représentant de bloc (avec ou sans réseau).'),
              const SizedBox(height: 14),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(Lpp552Colors.alertRed),
                  side: const BorderSide(color: Color(Lpp552Colors.alertRed), width: 2),
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EcranSosAscenseur(profil: profil)),
                  );
                },
                child: const Text('Ouvrir l\'écran SOS Ascenseur',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Écran 08 : Écran SOS Ascenseur (Alerte App Agent + Représentant de bloc + Secours GSM)
class EcranSosAscenseur extends StatelessWidget {
  final ProfilLocalLpp552 profil;
  const EcranSosAscenseur({super.key, required this.profil});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ascenseur · Bloc ${profil.bloc ?? 13}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                await Lpp552Service.instance.declencherSosAscenseur(
                  onModeHorsReseauActive: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Color(Lpp552Colors.alertRed),
                        content: Text('Mode sans réseau : Appel direct vers la loge de garde lancé.'),
                      ),
                    );
                  },
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Color(Lpp552Colors.alertRed),
                      content: Text(
                          'SOS envoyé dans l\'application de l\'Agent et du Représentant de votre bloc !'),
                    ),
                  );
                }
              },
              child: Container(
                width: 180,
                height: 180,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(Lpp552Colors.alertRed),
                ),
                alignment: Alignment.center,
                child: const Text('SOS',
                    style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Appuyez sur SOS pour alerter immédiatement l\'agent de sécurité ET le représentant de votre bloc dans l\'application.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(Lpp552Colors.alertRed)),
              onPressed: () => Lpp552Service.instance.appelerOuEnvoyerSmsSecoursSos(profil),
              icon: const Icon(Icons.phone),
              label: const Text('Appeler la loge de garde en direct'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => Lpp552Service.instance.appelerOuEnvoyerSmsSecoursSos(
                profil,
                appelerRepresentant: true,
              ),
              icon: const Icon(Icons.person_pin_circle_outlined),
              label: const Text('Appeler mon représentant de bloc'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Écran 09 : Signaler une panne d'équipement avec photo
class EcranSignalerPanne extends StatefulWidget {
  final ProfilLocalLpp552 profil;
  const EcranSignalerPanne({super.key, required this.profil});

  @override
  State<EcranSignalerPanne> createState() => _EcranSignalerPanneState();
}

class _EcranSignalerPanneState extends State<EcranSignalerPanne> {
  String _equipement = 'Ascenseur';
  final _descCtrl = TextEditingController();
  File? _photo;
  bool _envoi = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signaler une panne')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DropdownButtonFormField<String>(
            value: _equipement,
            items: ['Ascenseur', 'Porte du bloc', 'Portail principal', 'Éclairage / Pompe']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _equipement = v ?? 'Ascenseur'),
            decoration: const InputDecoration(labelText: 'Équipement concerné', filled: true),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description du problème constaté',
              filled: true,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final xfile = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
              if (xfile != null) setState(() => _photo = File(xfile.path));
            },
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(_photo == null ? 'Prendre une photo de la panne' : 'Photo ajoutée ✓'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _envoi
                ? null
                : () async {
                    setState(() => _envoi = true);
                    await Lpp552Service.instance.signalerPanneEquipement(
                      equipement: '$_equipement · Bloc ${widget.profil.bloc ?? 13}',
                      bloc: widget.profil.bloc ?? 13,
                      idAppart: widget.profil.idAppart ?? '13-05',
                      description: _descCtrl.text,
                      photoFile: _photo,
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
            child: const Text('Envoyer le signalement'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ONGLET 5 : ESPACE REPRÉSENTANT DE BLOC & INITIALISATION SERRURES JOUR 1 (ÉCRANS 19–29)
// =============================================================================
class OngletGererBlocRepresentant extends StatelessWidget {
  final ProfilLocalLpp552 profil;
  const OngletGererBlocRepresentant({super.key, required this.profil});

  @override
  Widget build(BuildContext context) {
    final int bloc = profil.bloc ?? 13;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Gérer le bloc $bloc', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Administration complète de vos 40 appartements dans l\'application.'),
        const SizedBox(height: 18),
        _LigneService(
          titre: 'Notifications & Alertes du bloc',
          sousTitre: 'SOS Ascenseur, demandes macarons, tags effacés',
          texteBouton: 'Ouvrir',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EcranNotificationsBloc(profil: profil)),
          ),
        ),
        _LigneService(
          titre: 'Saisir un paiement de cotisation',
          sousTitre: 'Trimestriel, partiel ou arriéré',
          texteBouton: 'Encaisser',
          onTap: () => _afficherDialogueEncaissement(context, bloc),
        ),
        _LigneService(
          titre: 'Créer un compte résident',
          sousTitre: 'Générer un code à 6 chiffres (valable 48 h)',
          texteBouton: 'Créer',
          onTap: () => _afficherDialogueCreationCompte(context, bloc),
        ),
        _LigneService(
          titre: 'Initialiser les 13 serrures (Jour 1)',
          sousTitre: 'Scanner en Bluetooth et sauvegarder lockData',
          texteBouton: 'Serrures',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EcranInitialisationSerruresJour1()),
          ),
        ),
      ],
    );
  }

  void _afficherDialogueEncaissement(BuildContext context, int bloc) {
    final appartCtrl = TextEditingController(text: '${bloc.toString().padLeft(2, '0')}-05');
    final montantCtrl = TextEditingController(text: '4500');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Encaisser une cotisation · Bloc $bloc'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: appartCtrl,
              decoration: const InputDecoration(labelText: 'Appartement (ex: 13-05)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: montantCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Montant encaissé (DZD)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              await Lpp552Service.instance.saisirPaiementCotisation(
                idAppart: appartCtrl.text.trim(),
                annee: 2026,
                montantDzd: int.tryParse(montantCtrl.text) ?? 4500,
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _afficherDialogueCreationCompte(BuildContext context, int bloc) {
    final nomCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final appartCtrl = TextEditingController(text: '${bloc.toString().padLeft(2, '0')}-05');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Créer un compte résident'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nomCtrl, decoration: const InputDecoration(labelText: 'Nom et prénom')),
            TextField(controller: telCtrl, decoration: const InputDecoration(labelText: 'Téléphone')),
            TextField(controller: appartCtrl, decoration: const InputDecoration(labelText: 'Appartement (ex: 13-05)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              final res = await Lpp552Service.instance.creerCompteAvecCode6Chiffres(
                nomPrenom: nomCtrl.text.trim(),
                telephone: telCtrl.text.trim(),
                idAppart: appartCtrl.text.trim(),
                choixProfil: 'OCCUPANT_PRINCIPAL',
              );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Code d\'activation (48 h)'),
                  content: Text(
                    'Remettez ce code à ${nomCtrl.text} :\n\n${res['code_6_chiffres']}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
              );
            },
            child: const Text('Générer code 6 chiffres'),
          ),
        ],
      ),
    );
  }
}

/// Écran 20 : Centre de Notifications & Messages du Représentant de Bloc
class EcranNotificationsBloc extends StatelessWidget {
  final ProfilLocalLpp552 profil;
  const EcranNotificationsBloc({super.key, required this.profil});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Notifications · Bloc ${profil.bloc ?? 13}')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: Supabase.instance.client
            .from('notifications_app')
            .select()
            .eq('bloc_cible', profil.bloc ?? 13)
            .order('creee_le', ascending: false)
            .limit(30),
        builder: (ctx, snap) {
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Text('Aucune notification en attente pour votre bloc.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final n = list[i];
              final bool critique = n['priorite'] == 'CRITIQUE_PLEIN_ECRAN';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: critique ? const Color(0xFFFFF5F5) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: critique ? const Color(Lpp552Colors.alertRed) : const Color(0xFFE2E6EA),
                    width: critique ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n['titre'] as String,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(n['corps_message'] as String),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// =============================================================================
// ÉCRAN SUPER ADMIN JOUR 1 : INITIALISATION BLUETOOTH DES 13 SERRURES TTLOCK
// =============================================================================
class EcranInitialisationSerruresJour1 extends StatefulWidget {
  const EcranInitialisationSerruresJour1({super.key});

  @override
  State<EcranInitialisationSerruresJour1> createState() => _EcranInitialisationSerruresJour1State();
}

class _EcranInitialisationSerruresJour1State extends State<EcranInitialisationSerruresJour1> {
  String? _serrureEnCours;
  String _statutScan = 'Touchez une serrure de la liste en étant devant la porte pour l\'initialiser.';

  void _initialiserSerrure(String idSerrure) {
    setState(() {
      _serrureEnCours = idSerrure;
      _statutScan = 'Recherche Bluetooth de $idSerrure en cours... Touchez la serrure pour la réveiller.';
    });

    Lpp552Service.instance.scannerEtInitialiserSerrureJour1(
      idSerrureCible: idSerrure,
      onSerrureDetectee: (nomBle, mac) {
        if (mounted) {
          setState(() => _statutScan = 'Serrure détectée ($nomBle · $mac). Extraction de lockData...');
        }
      },
      onInitialisationReussie: (lockData) {
        if (mounted) {
          setState(() {
            _serrureEnCours = null;
            _statutScan = '✓ Serrure $idSerrure initialisée et sauvegardée dans Supabase !';
          });
        }
      },
      onErreur: (err) {
        if (mounted) {
          setState(() {
            _serrureEnCours = null;
            _statutScan = 'Erreur : $err';
          });
        }
      },
    );
  }

  @override
  void dispose() {
    Lpp552Service.instance.arreterScanInitialisation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Initialisation des 13 Serrures (Jour 1)')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(Lpp552Colors.tealLightBg),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(_statutScan, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: Lpp552Service.instance.getListeDes13Serrures(),
              builder: (ctx, snap) {
                final serrures = snap.data ?? [];
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: serrures.length,
                  itemBuilder: (_, i) {
                    final s = serrures[i];
                    final String id = s['id_serrure'] as String;
                    final bool dejaInit = (s['lock_data'] as String?)?.isNotEmpty == true;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(
                          dejaInit ? Icons.check_circle : Icons.lock_outline,
                          color: dejaInit
                              ? const Color(Lpp552Colors.statusGreenTxt)
                              : const Color(0xFF5F6C72),
                        ),
                        title: Text(s['nom_affiche'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(dejaInit
                            ? 'Initialisée (${s['mac_address']})'
                            : 'Non initialisée · Prête à scanner'),
                        trailing: ElevatedButton(
                          onPressed: _serrureEnCours != null ? null : () => _initialiserSerrure(id),
                          style: ElevatedButton.styleFrom(minimumSize: const Size(110, 40)),
                          child: Text(dejaInit ? 'Réinitialiser' : 'Initialiser'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INTERFACES AGENT DE SÉCURITÉ, ALARME ROUGE & TECHNICIEN (ÉCRANS 30–36)
// =============================================================================
class EcranPosteGardeAgent extends StatefulWidget {
  final ProfilLocalLpp552 profil;
  const EcranPosteGardeAgent({super.key, required this.profil});

  @override
  State<EcranPosteGardeAgent> createState() => _EcranPosteGardeAgentState();
}

class _EcranPosteGardeAgentState extends State<EcranPosteGardeAgent> {
  final _plaqueCtrl = TextEditingController();
  Map<String, dynamic>? _resultatParking;

  Future<void> _verifierCode(String code) async {
    final res = await Lpp552Service.instance.controlerVehiculeParking(code);
    setState(() => _resultatParking = res ?? {'statut': 'INCONNU'});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agent de sécurité · Portail & Parking')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Contrôle du parking (QR ou Plaque)',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: MobileScanner(
                onDetect: (capture) {
                  final code = capture.barcodes.firstOrNull?.rawValue;
                  if (code != null) _verifierCode(code);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _plaqueCtrl,
            onSubmitted: _verifierCode,
            decoration: InputDecoration(
              hintText: 'Ou chercher par plaque / code (ex: 0D-05-1)',
              filled: true,
              fillColor: Colors.white,
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _verifierCode(_plaqueCtrl.text),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (_resultatParking != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _resultatParking!['statut'] == 'ACTIF'
                    ? const Color(Lpp552Colors.statusGreenBg)
                    : const Color(0xFFFCE8E6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _resultatParking!['statut'] == 'ACTIF'
                    ? '✓ VALIDE · Macaron ${_resultatParking!['code_macaron_court']} · Bloc ${_resultatParking!['bloc']} Appart. ${_resultatParking!['id_appart']}'
                    : '✗ INCONNU OU SUSPENDU · Aucun macaron actif trouvé.',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EcranAlarmePleinEcranRouge extends StatelessWidget {
  final Map<String, dynamic> notification;
  const EcranAlarmePleinEcranRouge({super.key, required this.notification});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(Lpp552Colors.alertRed),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ALERTE · AGENT DE SÉCURITÉ',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
              const SizedBox(height: 36),
              Text(notification['titre'] as String? ?? 'Urgence ascenseur',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(Lpp552Colors.alertDarkRed),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${notification['corps_message']}\nTél : ${notification['telephone_contact'] ?? ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.4),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(Lpp552Colors.alertDarkRed),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('J\'ai pris en charge'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EcranMaintenanceTechnicien extends StatelessWidget {
  final ProfilLocalLpp552 profil;
  const EcranMaintenanceTechnicien({super.key, required this.profil});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Technicien · Maintenance')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(Lpp552Colors.tealPrimary),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Visite mensuelle',
                          style: TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                      Text('5 000 DZD',
                          style: TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(Lpp552Colors.tealPrimary),
                    ),
                    onPressed: () async {
                      await Lpp552Service.instance.validerVisiteMensuelleTechnicien();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Visite mensuelle validée (5 000 DZD ajoutés aux dépenses).')),
                        );
                      }
                    },
                    child: const Text('Valider ma visite'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}