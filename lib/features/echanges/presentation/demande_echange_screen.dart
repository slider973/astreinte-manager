import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/caserne/caserne_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/reseau/connectivite.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/bouton_retour.dart';
import '../../../core/widgets/carre_creneau.dart';
import '../../../core/widgets/carte_douce.dart';
import '../../../core/widgets/primary_button.dart';
import '../../astreintes/domain/astreinte.dart';
import '../../astreintes/domain/astreintes_providers.dart';
import '../domain/demande_echange.dart';
import '../domain/echange.dart';
import '../domain/echanges_providers.dart';
import '../domain/issue_echange.dart';
import 'etat_echange.dart';
import 'widgets/detail_echange.dart';
import 'widgets/etapes_demande.dart';

/// **Proposer un échange** — le seul parcours du produit qui dépasse deux
/// touches, et il le peut : A n'est pas pressé (`design/073 § 1`).
///
/// Trois étapes au plus, **l'étape dans l'adresse** : « À qui ? », « Céder ou
/// échanger ? » (collègue seulement), « Vérifie ta demande ». Chaque
/// « Continuer » pousse l'étape suivante : le retour, du navigateur comme de
/// l'écran, recule d'une étape. Les choix faits voyagent dans l'adresse avec
/// elle, et un rechargement retrouve la page telle qu'on l'avait laissée.
class DemandeEchangeScreen extends ConsumerStatefulWidget {
  const DemandeEchangeScreen({
    required this.attributionId,
    required this.etape,
    super.key,
    this.cible,
    this.forme,
    this.retour,
  });

  final String attributionId;
  final EtapeDemande etape;

  /// `caserne`, ou l'identifiant du collègue.
  final String? cible;

  /// `echanger` pour un échange ; une cession sinon.
  final String? forme;

  /// L'attribution de B prise en retour.
  final String? retour;

  @override
  ConsumerState<DemandeEchangeScreen> createState() =>
      _DemandeEchangeScreenState();
}

/// Le mode choisi à l'étape 1, avant même qu'un collègue soit désigné.
enum _Mode { collegue, caserne }

class _DemandeEchangeScreenState extends ConsumerState<DemandeEchangeScreen> {
  _Mode? _mode;
  Collegue? _collegue;
  bool _echanger = false;
  GardeProposable? _rendue;

  bool _envoi = false;

  /// La demande est partie : la liste relue la montre engagée, et ce n'est
  /// plus une raison d'abandonner le parcours.
  bool _envoye = false;
  IssueEchange? _refus;

  @override
  void initState() {
    super.initState();
    _depuisAdresse();
  }

  @override
  void didUpdateWidget(DemandeEchangeScreen ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cible != widget.cible ||
        ancien.forme != widget.forme ||
        ancien.retour != widget.retour) {
      _depuisAdresse();
    }
  }

  /// L'adresse commande : les choix se relisent depuis elle. Le collègue et
  /// la garde rendue se résolvent quand leurs listes arrivent.
  void _depuisAdresse() {
    final cible = widget.cible;
    _mode = cible == null
        ? _mode
        : cible == cibleCaserne
        ? _Mode.caserne
        : _Mode.collegue;
    if (cible == null || cible == cibleCaserne) _collegue = null;
    _echanger = widget.forme == formeEchanger;
  }

  Astreinte? _astreinte() {
    for (final astreinte
        in ref.watch(astreintesControllerProvider).value?.donnees.astreintes ??
            const <Astreinte>[]) {
      if (astreinte.id == widget.attributionId) return astreinte;
    }
    return null;
  }

  /// Une adresse dont l'attribution n'est plus proposable ramène aux
  /// astreintes, avec la raison, **sans erreur**.
  void _abandonner() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      annoncerEchange(context, AppStrings.echangeIntrouvable);
      context.goNamed(AppRoutes.astreintesName);
    });
  }

  void _allerA(EtapeDemande etape) {
    unawaited(
      context.pushNamed<void>(
        AppRoutes.demandeEchangeName,
        queryParameters: AppRoutes.parametresDemandeEchange(
          attribution: widget.attributionId,
          etape: etape,
          cible: _mode == _Mode.caserne
              ? cibleCaserne
              : _collegueResolu()?.userId,
          echanger: _mode == _Mode.collegue && _echanger,
          retour: _echanger ? _rendueResolue()?.attributionId : null,
        ),
      ),
    );
  }

  Future<void> _envoyer(Astreinte astreinte) async {
    setState(() {
      _envoi = true;
      _refus = null;
    });
    final issue = await ref
        .read(echangesControllerProvider.notifier)
        .demander(
          attributionId: astreinte.id,
          garde: gardeDe(astreinte),
          cible: _mode == _Mode.caserne ? null : _collegueResolu(),
          rendue: _echanger ? _rendueResolue() : null,
        );
    if (!mounted) return;
    setState(() => _envoi = false);
    if (!issue.ok) {
      setState(() => _refus = issue);
      return;
    }
    _envoye = true;
    annoncerEchange(context, issue.message);
    // La pile du parcours est **remplacée**, pas empilée : on revient aux
    // astreintes, la feuille n'est pas rouverte.
    context.goNamed(AppRoutes.astreintesName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etatAstreintes = ref.watch(astreintesControllerProvider);
    final astreinte = _astreinte();
    final aujourdhui = ref.watch(horlogeAstreintesProvider)();
    final dejaEngagee = ref
        .watch(echangesControllerProvider)
        .value
        ?.enCoursSur(widget.attributionId);

    if (etatAstreintes.hasValue &&
        (astreinte == null ||
            !proposable(astreinte, aujourdhui) ||
            (dejaEngagee != null && !_envoi && !_envoye))) {
      _abandonner();
    }

    // Les deux listes dont dépend le bouton : l'écran se reconstruit à leur
    // arrivée, et les résolutions de l'adresse les lisent ensuite.
    ref.watch(colleguesEchangeProvider);
    final pairId = _collegueResolu()?.userId;
    if (pairId != null) ref.watch(gardesProposablesProvider(pairId));

    final heures =
        etatAstreintes.value?.donnees.heures ?? HeuresAffichage.defaut;
    final total = _mode == _Mode.caserne ? 2 : 3;
    final rang = switch (widget.etape) {
      EtapeDemande.qui => 1,
      EtapeDemande.quoi => 2,
      EtapeDemande.verifier => total,
    };
    final enLigne = ref.watch(enLigneProvider).value ?? true;
    final lectureSeule = ref.watch(lectureSeuleCaserneProvider);
    final grand = AppWindowClass.of(context).estLarge;

    final bouton = astreinte == null
        ? null
        : _bouton(astreinte, enLigne: enLigne, lectureSeule: lectureSeule);
    final refus = _refus;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        leading: const BoutonRetour(repli: AppRoutes.astreintesName),
        leadingWidth: BoutonRetour.largeur(context),
        title: const Text(AppStrings.echangeTitre),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            if (!enLigne)
              const AppBanner(
                variante: AppBannerVariante.horsLigne,
                texte: AppStrings.echangeHorsLigneRaison,
              )
            else if (lectureSeule)
              const AppBanner(
                variante: AppBannerVariante.lectureSeule,
                texte: AppStrings.echangeLectureSeuleRaison,
              )
            else if (refus != null)
              AppBanner(
                variante: AppBannerVariante.erreur,
                texte: refus.message,
                detail: refus.detail,
              )
            else
              const SizedBox.shrink(),
            Expanded(
              child: astreinte == null
                  ? const SizedBox.shrink()
                  : Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: grand ? 560 : AppSpacing.colonneMax,
                        ),
                        child: _contenu(
                          astreinte: astreinte,
                          heures: heures,
                          rang: rang,
                          total: total,
                          bouton: grand ? bouton : null,
                        ),
                      ),
                    ),
            ),
            if (!grand && bouton != null)
              Padding(
                padding: EdgeInsets.all(AppWindowClass.of(context).margePage),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.colonneMax,
                    ),
                    child: bouton,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _contenu({
    required Astreinte astreinte,
    required HeuresAffichage heures,
    required int rang,
    required int total,
    required Widget? bouton,
  }) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;
    final garde = gardeDe(astreinte);
    final (debut, fin) = bornes(heures, astreinte.creneau);

    return ListView(
      padding: EdgeInsets.fromLTRB(marge, AppSpacing.lg, marge, AppSpacing.xl),
      children: <Widget>[
        // La garde concernée, **toujours visible**.
        CarteDouce(
          child: Row(
            children: <Widget>[
              CarreCreneau(creneau: astreinte.creneau),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      gardeTitre(context, garde),
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      AppStrings.astreintesIntervalle(debut, fin),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          AppStrings.echangeEtape(rang, total),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        ...switch (widget.etape) {
          EtapeDemande.qui => <Widget>[
            EtapeQui(
              modeCollegue: _mode == _Mode.collegue,
              modeCaserne: _mode == _Mode.caserne,
              collegueId: widget.cible == cibleCaserne
                  ? null
                  : (_collegue?.userId ?? widget.cible),
              onCollegueMode: () => setState(() => _mode = _Mode.collegue),
              onCaserne: () => setState(() {
                _mode = _Mode.caserne;
                _collegue = null;
              }),
              onCollegue: (Collegue c) => setState(() {
                _mode = _Mode.collegue;
                if (_collegue?.userId != c.userId) _rendue = null;
                _collegue = c;
              }),
            ),
          ],
          EtapeDemande.quoi => <Widget>[
            EtapeQuoi(
              collegue: _collegueResolu(),
              echanger: _echanger,
              rendueId: _rendueResolue()?.attributionId,
              heures: heures,
              onCeder: () => setState(() {
                _echanger = false;
                _rendue = null;
              }),
              onEchanger: () => setState(() => _echanger = true),
              onRendue: (GardeProposable g) => setState(() => _rendue = g),
            ),
          ],
          EtapeDemande.verifier => <Widget>[
            EtapeVerifier(
              astreinte: astreinte,
              collegue: _mode == _Mode.caserne ? null : _collegueResolu(),
              rendue: _echanger ? _rendueResolue() : null,
              heures: heures,
            ),
          ],
        },
        if (bouton != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          bouton,
        ],
      ],
    );
  }

  /// Le collègue de l'adresse, résolu contre la liste chargée.
  Collegue? _collegueResolu() {
    final choisi = _collegue;
    if (choisi != null) return choisi;
    final id = widget.cible;
    if (id == null || id == cibleCaserne) return null;
    for (final c
        in ref.read(colleguesEchangeProvider).value ?? const <Collegue>[]) {
      if (c.userId == id) return c;
    }
    return null;
  }

  /// La garde rendue de l'adresse, résolue contre les gardes du collègue.
  GardeProposable? _rendueResolue() {
    final choisie = _rendue;
    if (choisie != null) return choisie;
    final id = widget.retour;
    final collegue = _collegueResolu();
    if (id == null || collegue == null) return null;
    for (final g
        in ref.read(gardesProposablesProvider(collegue.userId)).value ??
            const <GardeProposable>[]) {
      if (g.attributionId == id) return g;
    }
    return null;
  }

  Widget _bouton(
    Astreinte astreinte, {
    required bool enLigne,
    required bool lectureSeule,
  }) {
    final String? raison;
    final VoidCallback action;
    switch (widget.etape) {
      case EtapeDemande.qui:
        final pret =
            _mode == _Mode.caserne ||
            (_mode == _Mode.collegue && _collegueResolu() != null);
        raison = pret ? null : AppStrings.echangeChoisirQui;
        action = () => _allerA(
          _mode == _Mode.caserne ? EtapeDemande.verifier : EtapeDemande.quoi,
        );
        return PrimaryButton(
          libelle: AppStrings.echangeContinuer,
          icone: Icons.arrow_forward,
          onPressed: raison == null ? action : null,
          raisonDesactivation: raison,
        );
      case EtapeDemande.quoi:
        final manque = _collegueResolu() == null
            ? AppStrings.echangeChoisirQui
            : (_echanger && _rendueResolue() == null)
            ? AppStrings.echangeChoisirGarde
            : null;
        return PrimaryButton(
          libelle: AppStrings.echangeContinuer,
          icone: Icons.arrow_forward,
          onPressed: manque == null
              ? () => _allerA(EtapeDemande.verifier)
              : null,
          raisonDesactivation: manque,
        );
      case EtapeDemande.verifier:
        final pret =
            _mode == _Mode.caserne ||
            (_collegueResolu() != null && (!_echanger || _rendueResolue() != null));
        raison = lectureSeule
            ? AppStrings.echangeLectureSeuleRaison
            : !enLigne
            ? AppStrings.echangeHorsLigneRaison
            : pret
            ? null
            : AppStrings.echangeChoisirQui;
        return PrimaryButton(
          libelle: AppStrings.echangeEnvoyer,
          icone: Icons.send,
          chargement: _envoi,
          onPressed: raison == null && !_envoi
              ? () => unawaited(_envoyer(astreinte))
              : null,
          raisonDesactivation: raison,
        );
    }
  }
}
