import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/entete_section.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/parametres_caserne.dart';
import '../../domain/parametres_providers.dart';
import '../../domain/validation_parametres.dart';
import 'champ_choix.dart';
import 'champ_nombre.dart';
import 'ligne_surcharge.dart';

/// Le corps de l'écran « Paramètres » : six sections réglées, dans l'ordre où
/// on les règle.
///
/// Aucune carte, aucun accordéon : on doit lire l'état complet de la caserne
/// en faisant défiler une fois, comme on lit une page de registre.
class FormulaireParametres extends StatefulWidget {
  const FormulaireParametres({
    required this.etat,
    required this.onChange,
    required this.onToucher,
    required this.onModifierSurcharge,
    required this.onRetirerSurcharge,
    required this.onAjouterDate,
    super.key,
  });

  final EtatParametres etat;

  /// Une modification du brouillon, avec le champ qui l'a produite.
  final void Function(ParametresCaserne brouillon, {ChampParametre? champ})
  onChange;

  /// Un champ quitté : son erreur devient montrable.
  final ValueChanged<ChampParametre> onToucher;

  /// Ouvre la feuille de surcharge d'une clé existante (jour de semaine ou
  /// date).
  final void Function(String cle) onModifierSurcharge;

  final ValueChanged<String> onRetirerSurcharge;
  final VoidCallback onAjouterDate;

  @override
  State<FormulaireParametres> createState() => _FormulaireParametresState();
}

class _FormulaireParametresState extends State<FormulaireParametres> {
  late final TextEditingController _nom = TextEditingController(
    text: widget.etat.brouillon.nom,
  );
  late final TextEditingController _debut = TextEditingController(
    text: widget.etat.brouillon.debutJour,
  );
  late final TextEditingController _fin = TextEditingController(
    text: widget.etat.brouillon.finJour,
  );

  late final FocusNode _focusNom = FocusNode()
    ..addListener(() => _quitte(_focusNom, ChampParametre.nom));
  late final FocusNode _focusDebut = FocusNode()
    ..addListener(() => _quitte(_focusDebut, ChampParametre.debutJour));
  late final FocusNode _focusFin = FocusNode()
    ..addListener(() => _quitte(_focusFin, ChampParametre.finJour));

  @override
  void didUpdateWidget(FormulaireParametres ancien) {
    super.didUpdateWidget(ancien);
    // Le brouillon a changé ailleurs — relecture, enregistrement : les champs
    // texte suivent, sauf celui qu'on est en train d'écrire.
    _suivre(_nom, _focusNom, widget.etat.brouillon.nom);
    _suivre(_debut, _focusDebut, widget.etat.brouillon.debutJour);
    _suivre(_fin, _focusFin, widget.etat.brouillon.finJour);
  }

  @override
  void dispose() {
    for (final focus in <FocusNode>[_focusNom, _focusDebut, _focusFin]) {
      focus.dispose();
    }
    for (final controleur in <TextEditingController>[_nom, _debut, _fin]) {
      controleur.dispose();
    }
    super.dispose();
  }

  static void _suivre(
    TextEditingController controleur,
    FocusNode focus,
    String valeur,
  ) {
    if (!focus.hasFocus && controleur.text != valeur) controleur.text = valeur;
  }

  void _quitte(FocusNode focus, ChampParametre champ) {
    if (!focus.hasFocus) widget.onToucher(champ);
  }

  ParametresCaserne get _brouillon => widget.etat.brouillon;

  String? _erreur(ChampParametre champ) => widget.etat.erreurVisible(champ);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;
    final actif = !widget.etat.enregistrement;

    return ListView(
      padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.xl),
      children: <Widget>[
        const SizedBox(height: AppSpacing.lg),
        Text(
          AppStrings.parametresSousTitre,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        // --- La caserne ---------------------------------------------------
        const EnteteSection(
          titre: AppStrings.parametresSectionCaserne,
          compte: AppStrings.parametresSectionCaserneNote,
        ),
        const SizedBox(height: AppSpacing.md),
        Focus(
          focusNode: _focusNom,
          child: ChampTexte(
            libelle: AppStrings.parametresNom,
            texteInvite: AppStrings.parametresNomInvite,
            controleur: _nom,
            clavier: TextInputType.text,
            longueurMax: LimitesParametres.nomMax,
            actif: actif,
            erreur: _erreur(ChampParametre.nom),
            onChanged: (String texte) => widget.onChange(
              _brouillon.copyWith(nom: texte),
              champ: ChampParametre.nom,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ChampChoix(
          libelle: AppStrings.parametresFuseau,
          valeur: _brouillon.fuseau,
          options: AppStrings.fuseauxCaserne.map(
            (String cle, String _) =>
                MapEntry<String, String>(cle, AppStrings.fuseauLibelle(cle)),
          ),
          actif: actif,
          erreur: _erreur(ChampParametre.fuseau),
          onChange: (String choix) => widget.onChange(
            _brouillon.copyWith(fuseau: choix),
            champ: ChampParametre.fuseau,
          ),
        ),

        // --- Créneaux -----------------------------------------------------
        const EnteteSection(
          titre: AppStrings.parametresSectionCreneaux,
          compte: AppStrings.parametresSectionCreneauxNote,
        ),
        const SizedBox(height: AppSpacing.md),
        _ChampHeure(
          libelle: AppStrings.parametresDebutJour,
          controleur: _debut,
          focus: _focusDebut,
          actif: actif,
          erreur: _erreur(ChampParametre.debutJour),
          onChange: (String heure) => widget.onChange(
            _brouillon.copyWith(debutJour: heure),
            champ: ChampParametre.debutJour,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ChampHeure(
          libelle: AppStrings.parametresFinJour,
          controleur: _fin,
          focus: _focusFin,
          actif: actif,
          erreur: _erreur(ChampParametre.finJour),
          onChange: (String heure) => widget.onChange(
            _brouillon.copyWith(finJour: heure),
            champ: ChampParametre.finJour,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Note(
          AppStrings.parametresNuitDeduite(
            _brouillon.debutJour,
            _brouillon.finJour,
          ),
        ),

        // --- Effectif requis ----------------------------------------------
        const EnteteSection(
          titre: AppStrings.parametresSectionEffectif,
          compte: AppStrings.parametresSectionEffectifNote,
        ),
        const SizedBox(height: AppSpacing.md),
        ChampNombre(
          libelle: AppStrings.parametresEffectifJour,
          valeur: _brouillon.effectifJour,
          min: LimitesParametres.effectifMin,
          max: LimitesParametres.effectifMax,
          actif: actif,
          erreur: _erreur(ChampParametre.effectifJour),
          onQuitte: () => widget.onToucher(ChampParametre.effectifJour),
          onChange: (int valeur) => widget.onChange(
            _brouillon.copyWith(effectifJour: valeur),
            champ: ChampParametre.effectifJour,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ChampNombre(
          libelle: AppStrings.parametresEffectifNuit,
          valeur: _brouillon.effectifNuit,
          min: LimitesParametres.effectifMin,
          max: LimitesParametres.effectifMax,
          actif: actif,
          erreur: _erreur(ChampParametre.effectifNuit),
          onQuitte: () => widget.onToucher(ChampParametre.effectifNuit),
          onChange: (int valeur) => widget.onChange(
            _brouillon.copyWith(effectifNuit: valeur),
            champ: ChampParametre.effectifNuit,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _Note(AppStrings.parametresEffectifConsequence),

        // --- Surcharges ---------------------------------------------------
        const EnteteSection(
          titre: AppStrings.parametresSectionSurcharges,
          compte: AppStrings.parametresSectionSurchargesNote,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          AppStrings.parametresSurchargesSemaine,
          style: theme.textTheme.labelMedium,
        ),
        for (final JourSemaine jour in JourSemaine.values)
          LigneSurcharge(
            libelle: jour.libelle,
            surcharge: _brouillon.surchargeDe(jour),
            onModifier: () => widget.onModifierSurcharge(jour.cle),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          AppStrings.parametresSurchargesDates,
          style: theme.textTheme.labelMedium,
        ),
        if (_brouillon.surchargesDatees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: _Note(AppStrings.parametresSurchargesDatesVide),
          )
        else
          for (final SurchargeEffectif surcharge in _brouillon.surchargesDatees)
            LigneSurcharge(
              key: ValueKey<String>(surcharge.cle),
              libelle: surcharge.libelle,
              surcharge: surcharge,
              onModifier: () => widget.onModifierSurcharge(surcharge.cle),
              onRetirer: () => widget.onRetirerSurcharge(surcharge.cle),
            ),
        if (_erreur(ChampParametre.surcharges) != null)
          _Erreur(_erreur(ChampParametre.surcharges)!),
        const SizedBox(height: AppSpacing.sm),
        PrimaryButton(
          libelle: AppStrings.parametresSurchargeAjouterDate,
          variante: PrimaryButtonVariante.secondaire,
          icone: Icons.event,
          pleineLargeur: false,
          onPressed: actif ? widget.onAjouterDate : null,
          raisonDesactivation: actif ? null : AppStrings.saveEnCours,
        ),

        // --- Saisie des disponibilités ------------------------------------
        const EnteteSection(
          titre: AppStrings.parametresSectionSaisie,
          compte: AppStrings.parametresSectionSaisieNote,
        ),
        const SizedBox(height: AppSpacing.md),
        ChampNombre(
          libelle: AppStrings.parametresJourLimite,
          valeur: _brouillon.jourLimite,
          min: LimitesParametres.jourLimiteMin,
          max: LimitesParametres.jourLimiteMax,
          actif: actif,
          erreur: _erreur(ChampParametre.jourLimite),
          note: exempleJourLimite(_brouillon.jourLimite),
          onQuitte: () => widget.onToucher(ChampParametre.jourLimite),
          onChange: (int valeur) => widget.onChange(
            _brouillon.copyWith(jourLimite: valeur),
            champ: ChampParametre.jourLimite,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _Note(AppStrings.parametresJourLimiteConsequence),

        // --- Relances -----------------------------------------------------
        const EnteteSection(
          titre: AppStrings.parametresSectionRelances,
          compte: AppStrings.parametresSectionRelancesNote,
        ),
        const SizedBox(height: AppSpacing.md),
        _ChampDelai(
          libelle: AppStrings.parametresRelancePush,
          valeur: _brouillon.relancePushHeures,
          erreur: _erreur(ChampParametre.relancePush),
          actif: actif,
          onToucher: () => widget.onToucher(ChampParametre.relancePush),
          onChange: (int valeur) => widget.onChange(
            _brouillon.copyWith(relancePushHeures: valeur),
            champ: ChampParametre.relancePush,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ChampDelai(
          libelle: AppStrings.parametresRelanceEmail,
          valeur: _brouillon.relanceEmailHeures,
          erreur: _erreur(ChampParametre.relanceEmail),
          actif: actif,
          onToucher: () => widget.onToucher(ChampParametre.relanceEmail),
          onChange: (int valeur) => widget.onChange(
            _brouillon.copyWith(relanceEmailHeures: valeur),
            champ: ChampParametre.relanceEmail,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ChampDelai(
          libelle: AppStrings.parametresRapportRetard,
          valeur: _brouillon.rapportRetardHeures,
          erreur: _erreur(ChampParametre.rapportRetard),
          actif: actif,
          onToucher: () => widget.onToucher(ChampParametre.rapportRetard),
          onChange: (int valeur) => widget.onChange(
            _brouillon.copyWith(rapportRetardHeures: valeur),
            champ: ChampParametre.rapportRetard,
          ),
        ),
      ],
    );
  }
}

/// « Les disponibilités de novembre 2026 se ferment le 15 octobre 2026 à
/// 23:59. » — la conséquence du jour limite, avec de vraies dates.
///
/// Le mois donné en exemple est le prochain à saisir (M+1), comme les périodes
/// créées par le cron (`docs/SCHEMA.md § 2.5`).
String exempleJourLimite(int jourLimite, {DateTime? maintenant}) {
  final aujourdhui = maintenant ?? DateTime.now();
  final mois = DateTime(aujourdhui.year, aujourdhui.month + 1);
  final limite = DateTime(aujourdhui.year, aujourdhui.month);

  return AppStrings.parametresJourLimiteExemple(
    '${AppStrings.moisLongs[mois.month - 1]} ${mois.year}',
    AppStrings.dateLongue(
      jour: jourLimite,
      mois: limite.month,
      annee: limite.year,
    ),
  );
}

/// Une heure d'affichage : « 07:00 », clavier numérique, deux-points posé
/// tout seul.
class _ChampHeure extends StatelessWidget {
  const _ChampHeure({
    required this.libelle,
    required this.controleur,
    required this.focus,
    required this.actif,
    required this.onChange,
    this.erreur,
  });

  final String libelle;
  final TextEditingController controleur;
  final FocusNode focus;
  final bool actif;
  final ValueChanged<String> onChange;
  final String? erreur;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    child: ChampTexte(
      libelle: libelle,
      texteInvite: AppStrings.parametresHeureInvite,
      controleur: controleur,
      clavier: TextInputType.datetime,
      actif: actif,
      erreur: erreur,
      formateurs: const <TextInputFormatter>[_MasqueHeure()],
      onChanged: onChange,
    ),
  );
}

/// Un délai en heures : le même contrôle que les effectifs, avec son unité
/// écrite en toutes lettres à droite.
class _ChampDelai extends StatelessWidget {
  const _ChampDelai({
    required this.libelle,
    required this.valeur,
    required this.actif,
    required this.onChange,
    required this.onToucher,
    this.erreur,
  });

  final String libelle;
  final int valeur;
  final bool actif;
  final ValueChanged<int> onChange;
  final VoidCallback onToucher;
  final String? erreur;

  @override
  Widget build(BuildContext context) => ChampNombre(
    libelle: libelle,
    valeur: valeur,
    min: LimitesParametres.delaiMin,
    max: LimitesParametres.delaiMax,
    actif: actif,
    erreur: erreur,
    suffixe: AppStrings.parametresHeures(valeur),
    onQuitte: onToucher,
    onChange: onChange,
  );
}

/// Une phrase de contexte : ce que le réglage du dessus déplace.
class _Note extends StatelessWidget {
  const _Note(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      texte,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _Erreur extends StatelessWidget {
  const _Erreur(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: AppSpacing.lg,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                texte,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Masque « HH:MM » : on tape quatre chiffres, le deux-points se pose seul.
class _MasqueHeure extends TextInputFormatter {
  const _MasqueHeure();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue ancienne,
    TextEditingValue nouvelle,
  ) {
    final chiffres = nouvelle.text.replaceAll(RegExp('[^0-9]'), '');
    final gardes = chiffres.length > 4 ? chiffres.substring(0, 4) : chiffres;

    final texte = gardes.length <= 2
        ? gardes
        : '${gardes.substring(0, 2)}:${gardes.substring(2)}';

    return TextEditingValue(
      text: texte,
      selection: TextSelection.collapsed(offset: texte.length),
    );
  }
}
