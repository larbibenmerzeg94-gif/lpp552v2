// =============================================================================
// LPP 552 RÉGHAÏA – SERVICE FLUTTER COMPLET (SUPABASE + TTLOCK BLE + SOS)
// =============================================================================
// Dépendances à ajouter dans pubspec.yaml :
//   dependencies:
//     flutter:
//       sdk: flutter
//     supabase_flutter: ^2.8.0
//     ttlock_flutter: ^0.3.2
//     flutter_secure_storage: ^9.2.2
//     local_auth: ^2.3.0
//     url_launcher: ^6.3.1
//     crypto: ^3.0.5
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ttlock_flutter/ttlock.dart';
import 'package:url_launcher/url_launcher.dart';

/// Couleurs officielles de la charte UI/UX LPP 552 (Maquettes 42 écrans)
class Lpp552Colors {
  static const int tealPrimary = 0xFF14676B;
  static const int tealLightBg = 0xFFE2F2F2;
  static const int scaffoldBg = 0xFFF4F5F7;
  static const int alertRed = 0xFFA52524;
  static const int alertDarkRed = 0xFF7C1E23;
  static const int statusGreenBg = 0xFFE1F3EC;
  static const int statusGreenTxt = 0xFF146C43;
  static const int statusYellowBg = 0xFFFEF3C7;
  static const int statusYellowTxt = 0xFFB45309;
}

/// Profil mis en cache localement pour garantir le fonctionnement 100 % hors-ligne
class ProfilLocalLpp552 {
  final String userId;
  final String nomPrenom;
  final String telephone;
  final String role; // RESIDENT, REPRESENTANT, AGENT, TECHNICIEN, TRESORIER, SUPER_ADMIN
  final int? bloc;
  final String? idAppart;
  final String lien; // OCCUPANT, PROPRIETAIRE, LES_DEUX
  final String typeCompte; // PRINCIPAL, SECONDAIRE
  final String statut; // ACTIF, SUSPENDU, REVOQUE
  final DateTime dateExpirationAcces;

  ProfilLocalLpp552({
    required this.userId,
    required this.nomPrenom,
    required this.telephone,
    required this.role,
    this.bloc,
    this.idAppart,
    required this.lien,
    required this.typeCompte,
    required this.statut,
    required this.dateExpirationAcces,
  });

  bool get peutOuvrirPortes =>
      statut == 'ACTIF' && DateTime.now().isBefore(dateExpirationAcces.add(const Duration(days: 1)));

  bool get estRepresentant => role == 'REPRESENTANT' || role == 'SUPER_ADMIN';
  bool get estOccupant => lien == 'OCCUPANT' || lien == 'LES_DEUX';
  bool get estOccupantPrincipal => estOccupant && typeCompte == 'PRINCIPAL';

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'nomPrenom': nomPrenom,
        'telephone': telephone,
        'role': role,
        'bloc': bloc,
        'idAppart': idAppart,
        'lien': lien,
        'typeCompte': typeCompte,
        'statut': statut,
        'dateExpirationAcces': dateExpirationAcces.toIso8601String(),
      };

  factory ProfilLocalLpp552.fromJson(Map<String, dynamic> json) => ProfilLocalLpp552(
        userId: json['userId'] as String,
        nomPrenom: json['nomPrenom'] as String,
        telephone: json['telephone'] as String,
        role: json['role'] as String,
        bloc: json['bloc'] as int?,
        idAppart: json['idAppart'] as String?,
        lien: json['lien'] as String,
        typeCompte: json['typeCompte'] as String,
        statut: json['statut'] as String,
        dateExpirationAcces: DateTime.parse(json['dateExpirationAcces'] as String),
      );
}

/// Service central LPP 552 connectant les 42 écrans Flutter à Supabase et au SDK TTLock
class Lpp552Service {
  static final Lpp552Service instance = Lpp552Service._internal();
  Lpp552Service._internal();

  final SupabaseClient _db = Supabase.instance.client;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const String _kProfilCacheKey = 'lpp552_profil_cache_v2';
  static const String _kPinHashKey = 'lpp552_pin_sha256';
  static const String _kBiometrieKey = 'lpp552_biometrie_enabled';
  static const String _kSerruresCacheKey = 'lpp552_serrures_lockdata_cache';
  static const String _kLogePhoneCacheKey = 'lpp552_telephone_loge_garde';
  static const String _kRepresPhoneCacheKey = 'lpp552_telephone_representant_bloc';

  RealtimeChannel? _notifChannel;

  // ===========================================================================
  // 1. ENRÔLEMENT, CODE 6 CHIFFRES & DÉVERROUILLAGE PIN / BIOMÉTRIE (ÉCRANS 1 & 2)
  // ===========================================================================

  /// Écran 1 : Vérifie le numéro + le code à 6 chiffres (valable 48h) et lie l'appareil
  Future<ProfilLocalLpp552> activerAppareil({
    required String telephone,
    required String code6Chiffres,
    required String deviceId,
    String? fcmToken,
  }) async {
    final telClean = telephone.replaceAll(RegExp(r'\s+'), '');
    final codeHash = sha256.convert(utf8.encode(code6Chiffres.trim())).toString();

    final row = await _db
        .from('utilisateurs')
        .select('*, appartements(date_expiration_acces)')
        .eq('telephone', telClean)
        .maybeSingle();

    if (row == null) {
      throw Exception('Aucun compte trouvé pour ce numéro. Contactez votre représentant de bloc.');
    }

    // Si le compte est déjà actif sur un autre téléphone, refuser l'ouverture
    final existingDevice = row['device_id'] as String?;
    if (row['statut'] == 'ACTIF' && existingDevice != null && existingDevice != deviceId) {
      throw Exception('Ce compte est déjà lié à un autre téléphone. Demandez un nouveau code à votre représentant.');
    }

    // Vérifier le code à 6 chiffres et sa validité de 48 heures
    if (row['statut'] == 'EN_ATTENTE_ACTIVATION') {
      final storedHash = row['code_activation_hash'] as String?;
      final expireStr = row['code_expire_le'] as String?;
      if (storedHash != codeHash) {
        throw Exception('Code à 6 chiffres incorrect.');
      }
      if (expireStr != null && DateTime.now().isAfter(DateTime.parse(expireStr))) {
        throw Exception('Ce code a dépassé 48 heures. Demandez un nouveau code à votre représentant.');
      }
    }

    // Lier matériellement ce téléphone et activer le compte
    await _db.from('utilisateurs').update({
      'statut': 'ACTIF',
      'device_id': deviceId,
      'code_activation_hash': null, // Usage unique
      if (fcmToken != null) 'fcm_token': fcmToken,
    }).eq('id', row['id']);

    final expStr = row['appartements']?['date_expiration_acces'] as String? ?? '2026-12-31';
    final profil = ProfilLocalLpp552(
      userId: row['id'] as String,
      nomPrenom: row['nom_prenom'] as String,
      telephone: telClean,
      role: row['role'] as String,
      bloc: row['bloc'] as int?,
      idAppart: row['id_appart'] as String?,
      lien: row['lien'] as String,
      typeCompte: row['type_compte'] as String,
      statut: 'ACTIF',
      dateExpirationAcces: DateTime.parse(expStr),
    );

    await _secureStorage.write(key: _kProfilCacheKey, value: jsonEncode(profil.toJson()));
    await _rafraichirCacheSerruresEtContacts(profil);
    return profil;
  }

  /// Écran 2 : Enregistre le code PIN personnel et le choix biométrique
  Future<void> enregistrerCodePinEtBiometrie({
    required String codePin,
    required bool activerBiometrie,
  }) async {
    final hash = sha256.convert(utf8.encode(codePin)).toString();
    await _secureStorage.write(key: _kPinHashKey, value: hash);
    await _secureStorage.write(key: _kBiometrieKey, value: activerBiometrie.toString());
  }

  /// Déverrouillage rapide à l'ouverture de l'application (100 % hors-ligne)
  Future<bool> deverrouillerParBiometrieOuPin({String? codePinSaisi}) async {
    if (codePinSaisi != null) {
      final storedHash = await _secureStorage.read(key: _kPinHashKey);
      final inputHash = sha256.convert(utf8.encode(codePinSaisi)).toString();
      return storedHash != null && storedHash == inputHash;
    }

    final bioEnabled = await _secureStorage.read(key: _kBiometrieKey) == 'true';
    if (bioEnabled && await _localAuth.canCheckBiometrics) {
      return await _localAuth.authenticate(
        localizedReason: 'Déverrouillez l\'application Résidence LPP 552',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
    }
    return false;
  }

  /// Lit le profil en cache local et le synchronise en tâche de fond si le réseau est disponible
  Future<ProfilLocalLpp552?> chargerProfilCourant() async {
    final raw = await _secureStorage.read(key: _kProfilCacheKey);
    if (raw == null) return null;
    final profilLocal = ProfilLocalLpp552.fromJson(jsonDecode(raw) as Map<String, dynamic>);

    // Rafraîchissement non-bloquant depuis Supabase
    unawaited(_synchroniserProfilDepuisServeur(profilLocal.userId));
    return profilLocal;
  }

  Future<void> _synchroniserProfilDepuisServeur(String userId) async {
    try {
      final row = await _db
          .from('utilisateurs')
          .select('*, appartements(date_expiration_acces)')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 2));
      if (row != null) {
        final expStr = row['appartements']?['date_expiration_acces'] as String? ?? '2026-12-31';
        final updated = ProfilLocalLpp552(
          userId: row['id'] as String,
          nomPrenom: row['nom_prenom'] as String,
          telephone: row['telephone'] as String,
          role: row['role'] as String,
          bloc: row['bloc'] as int?,
          idAppart: row['id_appart'] as String?,
          lien: row['lien'] as String,
          typeCompte: row['type_compte'] as String,
          statut: row['statut'] as String,
          dateExpirationAcces: DateTime.parse(expStr),
        );
        await _secureStorage.write(key: _kProfilCacheKey, value: jsonEncode(updated.toJson()));
      }
    } catch (_) {
      // Hors-ligne : on conserve le cache local
    }
  }

  Future<void> _rafraichirCacheSerruresEtContacts(ProfilLocalLpp552 profil) async {
    try {
      // 1. Mettre en cache les lockData des serrures autorisées (Portail + Bloc du résident)
      final rows = await _db.from('serrures').select();
      final Map<String, String> lockMap = {};
      for (final r in rows) {
        final idSerrure = r['id_serrure'] as String;
        final blocSerrure = r['bloc'] as int?;
        final lockData = r['lock_data'] as String?;
        if (lockData != null &&
            (blocSerrure == null || blocSerrure == profil.bloc || profil.role == 'TECHNICIEN')) {
          lockMap[idSerrure] = lockData;
        }
      }
      await _secureStorage.write(key: _kSerruresCacheKey, value: jsonEncode(lockMap));

      // 2. Mettre en cache le numéro de la loge et du représentant de bloc pour le SOS hors-ligne
      final paramLoge = await _db
          .from('parametres')
          .select('valeur')
          .eq('cle', 'telephone_loge_garde')
          .maybeSingle();
      if (paramLoge != null) {
        await _secureStorage.write(key: _kLogePhoneCacheKey, value: paramLoge['valeur'] as String);
      }

      if (profil.bloc != null) {
        final repres = await _db
            .from('utilisateurs')
            .select('telephone')
            .eq('bloc', profil.bloc!)
            .eq('role', 'REPRESENTANT')
            .maybeSingle();
        if (repres != null) {
          await _secureStorage.write(key: _kRepresPhoneCacheKey, value: repres['telephone'] as String);
        }
      }
    } catch (_) {}
  }

  // ===========================================================================
  // 2. OUVERTURE BLUETOOTH & SYNCHRONISATION JIT DIRECTE (ÉCRANS 5, 6, 26, 27, 42)
  // ===========================================================================

  /// Écrans 5, 6 et 42 : Ouvre une serrure (Portail, Porte du bloc ou Ascenseur)
  /// et applique jusqu'à 2 tâches RFID en attente si le réseau répond en < 1,5 s.
  /// Si [ouvrirSansAttendre] vaut true (bouton de l'écran 6), ouvre immédiatement.
  Future<void> ouvrirPorteAvecSynchroJit({
    required String idSerrure, // ex: 'PORTAIL_PRINCIPAL', 'BLOC_13_PORTE', 'BLOC_13_ASC'
    bool ouvrirSansAttendre = false,
    void Function(int etapeCourante, int totalEtapes)? onProgressionJit,
    required void Function() onPorteOuverte,
    required void Function(String messageErreur) onErreur,
  }) async {
    final profil = await chargerProfilCourant();
    if (profil == null || !profil.peutOuvrirPortes) {
      onErreur('Votre accès est suspendu ou arrivé à expiration. Contactez votre représentant de bloc.');
      return;
    }

    final rawLocks = await _secureStorage.read(key: _kSerruresCacheKey);
    final Map<String, dynamic> lockMap = rawLocks != null ? jsonDecode(rawLocks) : {};
    final String? lockData = lockMap[idSerrure] as String?;

    if (lockData == null || lockData.isEmpty) {
      onErreur('Clé Bluetooth de la serrure ($idSerrure) non initialisée.');
      return;
    }

    // 1. Récupérer au maximum 2 tâches RFID en attente (sauf si "Ouvrir sans attendre")
    List<Map<String, dynamic>> taches = [];
    if (!ouvrirSansAttendre) {
      try {
        final res = await _db
            .from('taches_serrures')
            .select()
            .eq('id_serrure', idSerrure)
            .eq('statut', 'A_SYNCHRONISER')
            .order('creee_le', ascending: true)
            .limit(2)
            .timeout(const Duration(milliseconds: 1400));
        taches = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        // Hors réseau ou timeout > 1,4 s : on n'attend pas, ouverture directe !
        taches = [];
      }
    }

    // 2. Exécuter les tâches RFID éventuelles en Bluetooth avant l'ouverture
    for (int i = 0; i < taches.length; i++) {
      final tache = taches[i];
      final String tacheId = tache['id'] as String;
      final String typeTache = tache['type_tache'] as String;
      final String cardNumber = tache['card_number'] as String;

      onProgressionJit?.call(i + 1, taches.length);

      final completer = Completer<void>();
      if (typeTache == 'TASK_DELETE') {
        TTLock.deleteCard(cardNumber, lockData, () {
          unawaited(_marquerTacheExecutee(tacheId, profil.userId, true));
          if (!completer.isCompleted) completer.complete();
        }, (errorCode, errorMsg) {
          unawaited(_marquerTacheExecutee(tacheId, profil.userId, false));
          if (!completer.isCompleted) completer.complete();
        });
      } else if (typeTache == 'TASK_ADD' || typeTache == 'TASK_EXTEND') {
        final expStr = tache['date_validite_fin'] as String? ?? '2026-12-31';
        final startMs = DateTime.now().millisecondsSinceEpoch;
        final endMs = DateTime.parse(expStr).add(const Duration(hours: 23, minutes: 59)).millisecondsSinceEpoch;

        TTLock.modifyCardValidityPeriod(cardNumber, null, startMs, endMs, lockData, () {
          unawaited(_marquerTacheExecutee(tacheId, profil.userId, true));
          if (!completer.isCompleted) completer.complete();
        }, (errorCode, errorMsg) {
          unawaited(_marquerTacheExecutee(tacheId, profil.userId, false));
          if (!completer.isCompleted) completer.complete();
        });
      } else {
        completer.complete();
      }

      // Coupe-circuit de 2,5 s par tâche pour ne jamais bloquer le résident devant la porte
      await completer.future.timeout(const Duration(milliseconds: 2500), onTimeout: () {});
    }

    // 3. Déverrouiller physiquement la serrure en Bluetooth
    TTLock.controlLock(lockData, TTLockControlAction.unlock, (lockTime, electricQuantity, uniqueId) {
      onPorteOuverte();
      // Remise à l'heure silencieuse et journalisation en arrière-plan
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      TTLock.setLockTime(nowMs, lockData, () {}, (e, m) {});
      unawaited(_journaliserOuverture(idSerrure, profil, electricQuantity));
    }, (errorCode, errorMsg) {
      onErreur('Impossible de joindre la serrure en Bluetooth ($errorMsg). Rapprochez-vous de la porte.');
    });
  }

  Future<void> _marquerTacheExecutee(String tacheId, String userId, bool succes) async {
    try {
      await _db.from('taches_serrures').update({
        'statut': succes ? 'OK' : 'ECHEC',
        'remise_a_user': userId,
        'executee_le': DateTime.now().toIso8601String(),
      }).eq('id', tacheId);
    } catch (_) {}
  }

  Future<void> _journaliserOuverture(String idSerrure, ProfilLocalLpp552 profil, int batteriePct) async {
    try {
      await _db.from('serrures').update({
        'batterie_pct': batteriePct,
        'derniere_synchro': DateTime.now().toIso8601String(),
      }).eq('id_serrure', idSerrure);

      await _db.from('log_synchronisation').insert({
        'action': 'OUVERTURE_BLE',
        'id_serrure': idSerrure,
        'id_utilisateur': profil.userId,
        'id_appart': profil.idAppart,
        'succes': true,
        'detail': 'Batterie serrure: $batteriePct%',
      });
    } catch (_) {}
  }

  /// Écran 26 : Enrôler un nouveau tag RFID directement sur le lecteur de la porte du bloc
  Future<void> lireEtAssocierTagSurPorte({
    required int bloc,
    required String idAppart,
    required void Function() onAttenteBadgeSurSerrure,
    required void Function(String cardNumber) onTagAssocie,
    required void Function(String erreur) onErreur,
  }) async {
    final rawLocks = await _secureStorage.read(key: _kSerruresCacheKey);
    final Map<String, dynamic> lockMap = rawLocks != null ? jsonDecode(rawLocks) : {};
    final String idSerrureBloc = 'BLOC_${bloc}_PORTE';
    final String? lockData = lockMap[idSerrureBloc] as String?;

    if (lockData == null) {
      onErreur('Clé Bluetooth de la porte du bloc $bloc introuvable.');
      return;
    }

    final startMs = DateTime.now().millisecondsSinceEpoch;
    final endMs = DateTime(DateTime.now().year, 12, 31, 23, 59).millisecondsSinceEpoch;

    TTLock.addCard(null, startMs, endMs, lockData, () {
      onAttenteBadgeSurSerrure(); // "Posez le tag sur le lecteur de la porte d'entrée..."
    }, (cardNumber) async {
      // Le badge est déjà actif sur la porte du bloc ; on l'enregistre et on crée les tâches Portail + Ascenseur
      await _db.from('badges_rfid').upsert({
        'card_number': cardNumber,
        'id_appart': idAppart,
        'statut': 'ACTIF',
      });

      await _db.from('taches_serrures').insert([
        {
          'id_serrure': 'PORTAIL_PRINCIPAL',
          'id_appart': idAppart,
          'type_tache': 'TASK_ADD',
          'card_number': cardNumber,
          'date_validite_fin': '${DateTime.now().year}-12-31',
        },
        {
          'id_serrure': 'BLOC_${bloc}_ASC',
          'id_appart': idAppart,
          'type_tache': 'TASK_ADD',
          'card_number': cardNumber,
          'date_validite_fin': '${DateTime.now().year}-12-31',
        },
      ]);
      onTagAssocie(cardNumber);
    }, (errorCode, errorMsg) {
      onErreur('Erreur lors de la lecture du tag RFID : $errorMsg');
    });
  }

  /// Écran 27 : Révoquer un tag RFID perdu ou tous les tags d'un appartement
  Future<void> revoquerTagRfid({
    required int bloc,
    required String idAppart,
    String? cardNumberSpecifique,
  }) async {
    var query = _db.from('badges_rfid').select('card_number').eq('id_appart', idAppart).eq('statut', 'ACTIF');
    if (cardNumberSpecifique != null) {
      query = query.eq('card_number', cardNumberSpecifique);
    }
    final tags = await query;

    for (final t in tags) {
      final String cardNum = t['card_number'] as String;
      await _db.from('taches_serrures').insert([
        {'id_serrure': 'PORTAIL_PRINCIPAL', 'id_appart': idAppart, 'type_tache': 'TASK_DELETE', 'card_number': cardNum},
        {'id_serrure': 'BLOC_${bloc}_PORTE', 'id_appart': idAppart, 'type_tache': 'TASK_DELETE', 'card_number': cardNum},
        {'id_serrure': 'BLOC_${bloc}_ASC', 'id_appart': idAppart, 'type_tache': 'TASK_DELETE', 'card_number': cardNum},
      ]);
      await _db.from('badges_rfid').update({'statut': 'REVOQUE'}).eq('card_number', cardNum).eq('id_appart', idAppart);
    }
  }

  // ===========================================================================
  // 3. URGENCE SOS ASCENSEUR, PORTAIL BLOQUÉ & NOTIFICATIONS APP (ÉCRANS 7, 8, 20, 33, 34)
  // ===========================================================================

  /// Écran 8 : Déclenche l'alerte SOS Ascenseur vers l'Agent + le Représentant de bloc
  /// et bascule en mode secours GSM/SMS si le réseau Internet ne répond pas en 2,5 s.
  Future<bool> declencherSosAscenseur({
    required void Function() onModeHorsReseauActive,
  }) async {
    final profil = await chargerProfilCourant();
    if (profil == null) return false;

    try {
      await _db
          .rpc('rpc_declencher_sos_ascenseur', params: {'p_user_id': profil.userId})
          .timeout(const Duration(milliseconds: 2500));
      return true; // Alerte envoyée en temps réel dans l'application (Agent + Représentant du bloc)
    } catch (_) {
      // Mode sans Internet (cage d'ascenseur) : déclenche la sirène/flash local et prépare le SMS/Appel
      onModeHorsReseauActive();
      await appelerOuEnvoyerSmsSecoursSos(profil);
      return false;
    }
  }

  /// Appel GSM direct vers la loge de garde ou SMS d'urgence vers le représentant du bloc
  Future<void> appelerOuEnvoyerSmsSecoursSos(ProfilLocalLpp552 profil, {bool appelerRepresentant = false}) async {
    final telLoge = await _secureStorage.read(key: _kLogePhoneCacheKey) ?? '0550000000';
    final telRepres = await _secureStorage.read(key: _kRepresPhoneCacheKey) ?? telLoge;
    final cible = appelerRepresentant ? telRepres : telLoge;

    final uriTel = Uri.parse('tel:$cible');
    if (await canLaunchUrl(uriTel)) {
      await launchUrl(uriTel);
    }
  }

  /// Écran 7 : Signaler que le portail principal est bloqué (déclenche l'écran 33 chez l'agent)
  Future<void> signalerPortailBloque() async {
    final profil = await chargerProfilCourant();
    if (profil == null) return;

    await _db.from('notifications_app').insert({
      'type_notif': 'ALERTE_PORTAIL_BLOQUE',
      'priorite': 'CRITIQUE_PLEIN_ECRAN',
      'bloc_cible': profil.bloc,
      'role_cible': 'AGENT',
      'id_appart_cible': profil.idAppart,
      'titre': 'Portail bloqué',
      'corps_message': 'Bloc ${profil.bloc} · Appartement ${profil.idAppart?.split('-').last} · ${profil.nomPrenom}',
      'telephone_contact': profil.telephone,
    });
  }

  /// Écrans 5, 20, 33 et 34 : Écoute en temps réel les notifications et alarmes SOS dans l'application
  void ecouterNotificationsTempsReel({
    required ProfilLocalLpp552 profil,
    required void Function(Map<String, dynamic> notification) onNouvelleNotification,
  }) {
    _notifChannel?.unsubscribe();
    _notifChannel = _db
        .channel('public:notifications_app_${profil.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications_app',
          callback: (payload) {
            final rec = payload.newRecord;
            final roleCible = rec['role_cible'] as String?;
            final blocCible = rec['bloc_cible'] as int?;
            final appartCible = rec['id_appart_cible'] as String?;

            // Filtrage intelligent selon le profil connecté :
            // - L'Agent reçoit toutes les alertes AGENT (SOS Ascenseur, Portail bloqué)
            // - Le Représentant reçoit toutes les alertes REPRESENTANT de son propre bloc
            // - Le Résident reçoit les notifications adressées à son appartement
            final pourAgent = profil.role == 'AGENT' && roleCible == 'AGENT';
            final pourRepresentant =
                profil.estRepresentant && roleCible == 'REPRESENTANT' && (blocCible == null || blocCible == profil.bloc);
            final pourResident = appartCible != null && appartCible == profil.idAppart && roleCible == 'RESIDENT';

            if (pourAgent || pourRepresentant || pourResident) {
              onNouvelleNotification(rec);
            }
          },
        )
        .subscribe();
  }

  // ===========================================================================
  // 4. COTISATIONS, CAISSES, COMPTES & MISE EN LOCATION (ÉCRANS 10–13, 21–25)
  // ===========================================================================

  /// Écran 21 : Saisir un paiement de cotisation (Complet, Partiel ou Arriéré) par le représentant
  Future<Map<String, dynamic>> saisirPaiementCotisation({
    required String idAppart,
    required int annee,
    required int montantDzd,
    bool estArriere = false,
  }) async {
    final profil = await chargerProfilCourant();
    final res = await _db.rpc('rpc_encaisser_cotisation', params: {
      'p_id_appart': idAppart,
      'p_annee': annee,
      'p_montant_dzd': montantDzd,
      'p_est_arriere': estArriere,
      'p_representant_id': profil?.userId,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Écran 22 : Fixer le montant annuel de la cotisation du bloc (ex: 2026 = 18 000 DZD, 2027 = 30 000 DZD)
  Future<void> fixerMontantCotisationAnnee({
    required int bloc,
    required int annee,
    required int montantAnnuelDzd,
    int nbTrimestres = 4,
  }) async {
    final profil = await chargerProfilCourant();
    await _db.from('cotisations_annuelles').upsert({
      'bloc': bloc,
      'annee': annee,
      'montant_annuel_dzd': montantAnnuelDzd,
      'nb_trimestres': nbTrimestres,
      'modifie_par': profil?.userId,
      'modifie_le': DateTime.now().toIso8601String(),
    }, onConflict: 'bloc,annee');
  }

  /// Écrans 23 & 24 : Créer un compte résident sans mot de passe et obtenir le code à 6 chiffres (48h)
  Future<Map<String, dynamic>> creerCompteAvecCode6Chiffres({
    required String nomPrenom,
    required String telephone,
    required String idAppart,
    required String choixProfil, // 'OCCUPANT_PRINCIPAL', 'FAMILLE_OCCUPANT', 'PROPRIETAIRE'
  }) async {
    final res = await _db.rpc('rpc_creer_compte_avec_code', params: {
      'p_nom_prenom': nomPrenom,
      'p_telephone': telephone.replaceAll(RegExp(r'\s+'), ''),
      'p_id_appart': idAppart,
      'p_choix_profil': choixProfil,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Écran 25 : Basculer un appartement en "Mise en location" ou "Propriétaire habite"
  Future<Map<String, dynamic>> basculerMiseEnLocation({
    required String idAppart,
    required bool estLoue,
    String? nomLocataire,
    String? telephoneLocataire,
  }) async {
    final res = await _db.rpc('rpc_basculer_mise_en_location', params: {
      'p_id_appart': idAppart,
      'p_est_loue': estLoue,
      'p_nom_locataire': nomLocataire,
      'p_tel_locataire': telephoneLocataire?.replaceAll(RegExp(r'\s+'), ''),
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Écrans 10 & 11 : Récupère la grille des 40 appartements du bloc (T1-T4, %, Arriérés)
  Future<List<Map<String, dynamic>>> getGrilleCotisationsBloc({
    required int bloc,
    required int annee,
  }) async {
    final rows = await _db
        .from('vue_grille_cotisations_appartements')
        .select()
        .eq('bloc', bloc)
        .eq('annee', annee)
        .order('num_appart', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  // ===========================================================================
  // 5. VISITEURS, PARKING MACARONS QR, MAINTENANCE & POP-UP AVIS (ÉCRANS 3, 4, 9, 14–18, 28–36)
  // ===========================================================================

  /// Écrans 3 & 4 : Récupère les annonces (Avis / Volontariat) auxquelles l'appartement n'a pas encore répondu
  Future<List<Map<String, dynamic>>> getAnnoncesObligatoiresNonTraitees({
    required int bloc,
    required String idAppart,
  }) async {
    final annonces = await _db
        .from('annonces_vie_residence')
        .select()
        .contains('blocs_cibles', [bloc])
        .order('cree_le', ascending: false);

    final dejaRepondu = await _db
        .from('reponses_annonces')
        .select('id_annonce')
        .eq('id_appart', idAppart);

    final Set<String> idsTraitement =
        dejaRepondu.map((r) => r['id_annonce'] as String).toSet();

    return List<Map<String, dynamic>>.from(
      annonces.where((a) => !idsTraitement.contains(a['id'] as String)),
    );
  }

  /// Écrans 3, 4 & 18 : Enregistre la réponse obligatoire ("J_AI_VU", "JE_PARTICIPE", "JE_NE_PEUX_PAS")
  Future<void> repondreAnnonce({
    required String idAnnonce,
    required String idAppart,
    required int bloc,
    required String reponse,
  }) async {
    final profil = await chargerProfilCourant();
    await _db.from('reponses_annonces').upsert({
      'id_annonce': idAnnonce,
      'id_appart': idAppart,
      'bloc': bloc,
      'reponse': reponse,
      'repondu_par': profil?.userId,
    }, onConflict: 'id_annonce,id_appart');
  }

  /// Écrans 16 & 17 : Déclarer un véhicule par l'occupant principal (génère le code Hex par trigger SQL)
  Future<void> declarerVehicule({
    required String idAppart,
    required int bloc,
    required String plaque,
    required String marqueModele,
    required String couleur,
    required String typeVehicule, // 'Voiture' ou 'Moto'
  }) async {
    final profil = await chargerProfilCourant();
    if (profil == null || !profil.estOccupantPrincipal) {
      throw Exception('Seul le compte principal de l\'occupant peut déclarer un véhicule.');
    }
    await _db.from('vehicules_parking').insert({
      'id_appart': idAppart,
      'bloc': bloc,
      'id_occupant': profil.userId,
      'plaque': plaque.trim().toUpperCase(),
      'marque_modele': marqueModele.trim(),
      'couleur': couleur.trim(),
      'type_vehicule': typeVehicule,
      'statut': 'EN_ATTENTE',
    });
  }

  /// Écran 28 : Associer un macaron physique par scan ou saisie du code par le représentant de bloc
  Future<void> associerMacaronAuVehicule({
    required String idVehicule,
    required String codeMacaronScanne,
  }) async {
    final profil = await chargerProfilCourant();
    final veh = await _db.from('vehicules_parking').select().eq('id', idVehicule).single();
    final codeAttenduCourt = veh['code_macaron_court'] as String;
    final codeAttenduComplet = veh['code_macaron_complet'] as String;
    final cleanScan = codeMacaronScanne.trim().toUpperCase();

    if (cleanScan != codeAttenduCourt && cleanScan != codeAttenduComplet) {
      throw Exception('Ce macaron ($cleanScan) ne correspond pas au code attendu ($codeAttenduCourt).');
    }

    await _db.from('vehicules_parking').update({
      'statut': 'ACTIF',
      'remis_par': profil?.userId,
      'date_remise': DateTime.now().toIso8601String(),
    }).eq('id', idVehicule);
  }

  /// Écran 32 : Contrôle d'un véhicule au parking par l'Agent de sécurité (par QR code ou par plaque)
  /// Ne renvoie jamais le nom du résident ni aucune donnée financière.
  Future<Map<String, dynamic>?> controlerVehiculeParking(String qrOuPlaque) async {
    final q = qrOuPlaque.trim().toUpperCase();
    final row = await _db
        .from('vehicules_parking')
        .select('id_appart, bloc, plaque, marque_modele, couleur, code_macaron_court, statut')
        .or('code_macaron_court.eq.$q,code_macaron_complet.eq.$q,plaque.ilike.%$q%')
        .maybeSingle();
    return row;
  }

  /// Écran 9 : Signaler une panne d'équipement par un résident (avec upload photo optionnel)
  Future<void> signalerPanneEquipement({
    required String equipement,
    required int bloc,
    required String idAppart,
    required String description,
    File? photoFile,
  }) async {
    String? storagePath;
    if (photoFile != null) {
      final fileName = 'panne_${bloc}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _db.storage.from('photos-pannes').upload(fileName, photoFile);
      storagePath = fileName;
    }

    await _db.from('pannes_maintenance').insert({
      'equipement': equipement,
      'bloc': bloc,
      'declare_par_appart': idAppart,
      'description_probleme': description,
      'photo_panne_path': storagePath,
      'statut_panne': 'SIGNALEE',
    });
  }

  /// Écran 35 : Valider la visite mensuelle par le Technicien (crée automatiquement la dépense de 5 000 DZD)
  Future<void> validerVisiteMensuelleTechnicien() async {
    final profil = await chargerProfilCourant();
    await _db.rpc('rpc_valider_visite_mensuelle_technicien', params: {
      'p_technicien_id': profil?.userId,
    });
  }

  // ===========================================================================
  // 6. INITIALISATION MATÉRIELLE DES 13 SERRURES LE JOUR 1 (SUPER ADMIN)
  // ===========================================================================

  /// Récupère la liste des 13 serrures de la résidence et leur état d'initialisation
  Future<List<Map<String, dynamic>>> getListeDes13Serrures() async {
    final rows = await _db.from('serrures').select().order('id_serrure', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Écran Super Admin "Initialisation Jour 1" :
  /// Scanne la serrure TTLock à proximité (en mode couplage), l'initialise via `TTLock.initLock`,
  /// et sauvegarde automatiquement son `lock_data` maître et son `mac_address` dans Supabase !
  void scannerEtInitialiserSerrureJour1({
    required String idSerrureCible, // ex: 'PORTAIL_PRINCIPAL', 'BLOC_13_PORTE', 'BLOC_13_ASC'
    required void Function(String nomBleDetecte, String mac) onSerrureDetectee,
    required void Function(String lockDataSauvegarde) onInitialisationReussie,
    required void Function(String messageErreur) onErreur,
  }) {
    bool dejaLance = false;

    TTLock.startScanLock((scanModel) {
      // On ne prend que la serrure en mode d'initialisation (isInited == false) à proximité immédiate
      if (!dejaLance && !scanModel.isInited) {
        dejaLance = true;
        TTLock.stopScanLock();
        onSerrureDetectee(scanModel.lockName, scanModel.lockMac);

        final Map<String, dynamic> lockMapParam = {
          'lockMac': scanModel.lockMac,
          'lockVersion': scanModel.lockVersion,
          'isInited': scanModel.isInited,
        };

        TTLock.initLock(lockMapParam, (lockData) async {
          try {
            // Sauvegarde automatique dans la table `serrures` de Supabase
            await _db.from('serrures').update({
              'mac_address': scanModel.lockMac,
              'lock_data': lockData,
              'derniere_synchro': DateTime.now().toIso8601String(),
            }).eq('id_serrure', idSerrureCible);

            // Mise à jour immédiate du cache local du téléphone
            final rawLocks = await _secureStorage.read(key: _kSerruresCacheKey);
            final Map<String, dynamic> cacheMap = rawLocks != null ? jsonDecode(rawLocks) : {};
            cacheMap[idSerrureCible] = lockData;
            await _secureStorage.write(key: _kSerruresCacheKey, value: jsonEncode(cacheMap));

            onInitialisationReussie(lockData);
          } catch (e) {
            onErreur('Serrure initialisée, mais erreur de sauvegarde Supabase : $e');
          }
        }, (errorCode, errorMsg) {
          onErreur('Échec de l\'initialisation TTLock ($errorCode) : $errorMsg');
        });
      }
    });
  }

  /// Arrête manuellement le scan Bluetooth d'initialisation
  void arreterScanInitialisation() {
    TTLock.stopScanLock();
  }

}