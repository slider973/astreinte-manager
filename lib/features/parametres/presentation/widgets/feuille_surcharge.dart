import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/champ_texte.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/parametres_caserne.dart';
import '../../domain/validation_parametres.dart';
import 'champ_nombre.dart';

/// Règle une surcharge d'effectif, et la rend.
///
/// Rend `null` si la feuille a été refermée sans appliquer. Une surcharge
/// **vide** veut dire « reviens à l'effectif par défaut » : c'est un retrait,
/// pas une absence de réponse, d'où la distinction avec `null`.
///
/// La même feuille sert aux jours de semaine et aux dates ; seule la clé
/// change de nature. Pour une date, elle est saisie ici ([dateSaisie]) parce
/// qu'aucun sélecteur Material n'existe en français dans cette application —
/// `flutter_localizations` n'est pas embarqué, et un calendrier en anglais
/// serait un texte non traduit au milieu de l'écran.
Future<SurchargeEffectif?> afficherSurcharge({
  required BuildContext context,
  required String titre,
  required ParametresCaserne parametres,
  String? cle,
  SurchargeEffectif? surcharge,
  bool dateSaisie = false,
  Set<String> clesExistantes = const <String>{},
}) => showModalBottomSheet<SurchargeEffectif>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => _FeuilleSurcharge(
    titre: titre,
    parametres: parametres,
    cle: cle,
    surcharge: surcharge,
    dateSaisie: dateSaisie,
    clesExistantes: clesExistantes,
  ),
);

class _FeuilleSurcharge extends StatefulWidget {
  const _FeuilleSurcharge({
    required this.titre,
    required this.parametres,
    required this.dateSaisie,
    required this.clesExistantes,
    this.cle,
    this.surcharge,
  });

  final String titre;
  final ParametresCaserne parametres;
  final String? cle;
  final SurchargeEffectif? surcharge;
  final bool dateSaisie;
  final Set<String> clesExistantes;

  @override
  State<_FeuilleSurcharge> createState() => _FeuilleSurchargeState();
}

class _FeuilleSurchargeState extends State<_FeuilleSurcharge> {
  late int? _jour = widget.surcharge?.effectifJour;
  late int? _nuit = widget.surcharge?.effectifNuit;
  late final TextEditingController _date = TextEditingController(
    text: widget.surcharge?.date == null
        ? ''
        : formaterDateCourte(widget.surcharge!.date!),
  );
  String? _erreurDate;

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  bool get _pose => _jour != null || _nuit != null;

  void _appliquer() {
    final cle = _cleChoisie();
    if (cle == null) return;

    Navigator.of(context).pop<SurchargeEffectif>(
      SurchargeEffectif(cle: cle, effectifJour: _jour, effectifNuit: _nuit),
    );
  }

  /// Le retrait est une réponse, pas un abandon : il repart avec la clé et
  /// deux effectifs vides.
  void _revenirAuDefaut() {
    final cle = widget.cle ?? widget.surcharge?.cle;
    if (cle == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop<SurchargeEffectif>(SurchargeEffectif(cle: cle));
  }

  String? _cleChoisie() {
    if (!widget.dateSaisie) return widget.cle ?? widget.surcharge?.cle;

    final date = lireDateCourte(_date.text);
    if (date == null) {
      setState(() => _erreurDate = AppStrings.parametresDateInvalide);
      return null;
    }
    final cle = cleDate(date);
    if (cle != widget.surcharge?.cle && widget.clesExistantes.contains(cle)) {
      setState(() => _erreurDate = AppStrings.parametresSurchargeDateExistante);
      return null;
    }
    setState(() => _erreurDate = null);
    return cle;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(widget.titre, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppStrings.parametresSurchargeDefautRappel(
                  widget.parametres.effectifJour,
                  widget.parametres.effectifNuit,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (widget.dateSaisie) ...<Widget>[
                ChampTexte(
                  libelle: AppStrings.parametresSurchargeDate,
                  texteInvite: AppStrings.parametresSurchargeDateInvite,
                  controleur: _date,
                  clavier: TextInputType.datetime,
                  autofocus: widget.surcharge == null,
                  erreur: _erreurDate,
                  formateurs: const <TextInputFormatter>[_MasqueDate()],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _ReglageCreneau(
                libelleCase: AppStrings.parametresSurchargeFixerJour,
                libelleNombre: AppStrings.parametresCreneauJourLibelle,
                defaut: widget.parametres.effectifJour,
                valeur: _jour,
                onChange: (int? valeur) => setState(() => _jour = valeur),
              ),
              const SizedBox(height: AppSpacing.lg),
              _ReglageCreneau(
                libelleCase: AppStrings.parametresSurchargeFixerNuit,
                libelleNombre: AppStrings.parametresCreneauNuitLibelle,
                defaut: widget.parametres.effectifNuit,
                valeur: _nuit,
                onChange: (int? valeur) => setState(() => _nuit = valeur),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                libelle: AppStrings.parametresSurchargeAppliquer,
                icone: Icons.check,
                onPressed: _pose ? _appliquer : null,
                raisonDesactivation: _pose
                    ? null
                    : AppStrings.parametresSurchargeIncomplete,
              ),
              if (widget.surcharge != null) ...<Widget>[
                const SizedBox(height: AppSpacing.entreCibles),
                PrimaryButton(
                  libelle: AppStrings.parametresSurchargeRevenirDefaut,
                  variante: PrimaryButtonVariante.secondaire,
                  icone: Icons.restart_alt,
                  onPressed: _revenirAuDefaut,
                ),
              ],
              const SizedBox(height: AppSpacing.entreCibles),
              PrimaryButton(
                libelle: AppStrings.actionAnnuler,
                variante: PrimaryButtonVariante.secondaire,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un créneau de la feuille : on le laisse au défaut, ou on lui fixe un
/// nombre. Les deux états sont visibles en même temps — la case dit lequel est
/// choisi, le nombre n'apparaît que s'il compte.
class _ReglageCreneau extends StatelessWidget {
  const _ReglageCreneau({
    required this.libelleCase,
    required this.libelleNombre,
    required this.defaut,
    required this.valeur,
    required this.onChange,
  });

  final String libelleCase;
  final String libelleNombre;
  final int defaut;
  final int? valeur;
  final ValueChanged<int?> onChange;

  @override
  Widget build(BuildContext context) {
    final courant = valeur;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CheckboxListTile(
          value: courant != null,
          onChanged: (bool? coche) => onChange(coche ?? false ? defaut : null),
          title: Text(libelleCase),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        if (courant != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          ChampNombre(
            libelle: libelleNombre,
            valeur: courant,
            min: LimitesParametres.effectifMin,
            max: LimitesParametres.effectifMax,
            onChange: onChange,
          ),
        ],
      ],
    );
  }
}

/// Masque « JJ/MM/AAAA » : on tape huit chiffres, les barres se posent seules.
class _MasqueDate extends TextInputFormatter {
  const _MasqueDate();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue ancienne,
    TextEditingValue nouvelle,
  ) {
    final chiffres = nouvelle.text.replaceAll(RegExp('[^0-9]'), '');
    final gardes = chiffres.length > 8 ? chiffres.substring(0, 8) : chiffres;

    final tampon = StringBuffer();
    for (var index = 0; index < gardes.length; index++) {
      if (index == 2 || index == 4) tampon.write('/');
      tampon.write(gardes[index]);
    }

    final texte = tampon.toString();
    return TextEditingValue(
      text: texte,
      selection: TextSelection.collapsed(offset: texte.length),
    );
  }
}
