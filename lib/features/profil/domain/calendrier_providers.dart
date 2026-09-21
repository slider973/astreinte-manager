import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env.dart';
import '../../../core/plateforme/presse_papiers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/calendrier_repository.dart';

/// Le dépôt du jeton d'abonnement. Surchargé par un faux dans les tests.
final Provider<CalendrierRepository> calendrierRepositoryProvider =
    Provider<CalendrierRepository>(
      (ref) => SupabaseCalendrierRepository(ref.watch(supabaseClientProvider)),
    );

/// L'adresse d'abonnement au calendrier, composée à partir du jeton.
///
/// **Le jeton vient du serveur, la base de l'adresse vient de la configuration
/// de compilation** (`SUPABASE_URL`) : c'est le même découpage que partout
/// ailleurs, et il évite que l'application se croie capable de deviner l'URL
/// d'un environnement qu'elle ne connaît pas.
///
/// La forme canonique se termine par `.ics` : plusieurs agendas — Outlook en
/// tête — décident du type de contenu d'après le suffixe de l'URL avant même de
/// lire l'en-tête du serveur (`supabase/functions/ics-feed/jeton.ts`).
@immutable
class AdresseAbonnement {
  const AdresseAbonnement({required this.base, required this.jeton});

  /// `SUPABASE_URL`, sans barre oblique finale.
  final String base;

  final String jeton;

  /// `https://…/functions/v1/ics-feed/<jeton>.ics`.
  String get url {
    final racine = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$racine/functions/v1/ics-feed/$jeton.ics';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdresseAbonnement && other.base == base && other.jeton == jeton;

  @override
  int get hashCode => Object.hash(base, jeton);
}

/// Où en est le bloc « Ajouter à mon calendrier ».
@immutable
class EtatCalendrier {
  const EtatCalendrier({
    this.adresse,
    this.enCours = false,
    this.echec,
    this.copie = false,
    this.regenere = false,
  });

  /// `null` tant que la première lecture n'a pas répondu, ou après un échec.
  final AdresseAbonnement? adresse;

  /// Vrai pendant la lecture **comme** pendant la régénération : les deux
  /// occupent le même bloc, et aucune des deux ne peut être lancée deux fois.
  final bool enCours;

  final EchecAbonnement? echec;

  /// Vrai juste après une copie réussie dans le presse-papiers. Retombe à la
  /// régénération suivante : une confirmation ne survit pas à ce qu'elle
  /// confirmait.
  final bool copie;

  /// Vrai juste après une régénération. L'écran le dit **sur place** : dans une
  /// PWA installée, rien d'autre ne signale qu'une adresse vient de mourir.
  final bool regenere;

  String? get message => echec?.message;

  bool get prete => adresse != null;
}

/// Lit le jeton d'abonnement, compose l'adresse, la copie, la régénère.
class CalendrierController extends Notifier<EtatCalendrier> {
  @override
  EtatCalendrier build() {
    // La première lecture part toute seule : le bloc n'a qu'un contenu utile —
    // l'adresse — et un bouton « Afficher mon lien » ne serait qu'une étape de
    // plus devant la seule chose qu'on est venu chercher.
    unawaited(Future<void>.microtask(charger));
    return const EtatCalendrier(enCours: true);
  }

  /// Le presse-papiers, injecté : aucun test n'écrit dans celui du système.
  Future<bool> Function(String) get _copier => ref.read(pressePapiersProvider);

  Future<void> charger() async {
    state = EtatCalendrier(adresse: state.adresse, enCours: true);
    await _demander((CalendrierRepository depot) => depot.lireJeton());
  }

  /// Régénère le lien. L'ancienne adresse cesse de répondre immédiatement
  /// (`rotate_ics_token`, migration `0029`).
  Future<bool> regenerer() async {
    if (state.enCours) return false;
    state = EtatCalendrier(adresse: state.adresse, enCours: true);
    final jeton = await _demander(
      (CalendrierRepository depot) => depot.regenererJeton(),
      regenere: true,
    );
    return jeton;
  }

  /// Copie l'adresse. Rend faux quand il n'y a rien à copier, ou quand le
  /// navigateur a refusé — auquel cas l'adresse reste sélectionnable à l'écran,
  /// et c'est la raison pour laquelle elle y est affichée en entier.
  Future<bool> copier() async {
    final adresse = state.adresse;
    if (adresse == null) return false;

    final copie = await _copier(adresse.url);
    state = EtatCalendrier(adresse: adresse, copie: copie);
    return copie;
  }

  Future<bool> _demander(
    Future<String> Function(CalendrierRepository) action, {
    bool regenere = false,
  }) async {
    try {
      final jeton = await action(ref.read(calendrierRepositoryProvider));
      state = EtatCalendrier(
        adresse: AdresseAbonnement(
          base: ref.read(envProvider).supabaseUrl,
          jeton: jeton,
        ),
        regenere: regenere,
      );
      return true;
    } on EchecAbonnement catch (echec) {
      // **L'ancienne adresse n'est pas effacée de l'écran en cas d'échec de
      // régénération** : si l'appel n'est pas parti, elle marche encore, et la
      // faire disparaître ferait croire à une coupure qui n'a pas eu lieu.
      state = EtatCalendrier(adresse: state.adresse, echec: echec);
      return false;
    } on Object {
      state = EtatCalendrier(
        adresse: state.adresse,
        echec: const EchecAbonnement(ErreurAbonnement.inconnue),
      );
      return false;
    }
  }
}

final NotifierProvider<CalendrierController, EtatCalendrier>
calendrierControllerProvider =
    NotifierProvider<CalendrierController, EtatCalendrier>(
      CalendrierController.new,
      isAutoDispose: true,
    );

/// Écrit une chaîne dans le presse-papiers et dit si ça a marché.
///
/// Surchargé par un faux dans les tests : le presse-papiers du système est un
/// canal de plateforme, il n'existe pas sous `flutter test`.
typedef EcrirePressePapiers = Future<bool> Function(String);

final Provider<EcrirePressePapiers> pressePapiersProvider =
    Provider<EcrirePressePapiers>((ref) => copierDansPressePapiers);
