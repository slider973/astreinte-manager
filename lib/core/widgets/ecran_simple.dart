import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';
import 'app_banner.dart';

/// L'ossature des écrans sans navigation : connexion, invitation, accueil
/// d'un nouveau membre.
///
/// `AppScaffold` porte une navigation à cinq destinations qu'un visiteur non
/// connecté n'a pas le droit d'avoir, et qu'un nouvel arrivant n'a pas encore
/// à découvrir. On reprend donc ses règles — bannière pleine largeur sous le
/// haut d'écran, zones sûres, marge de page selon la classe de fenêtre — sans
/// sa navigation.
///
/// La colonne est bornée à 420 dp : une adresse e-mail, six chiffres ou trois
/// gestes d'installation n'ont jamais besoin de la largeur d'un écran de
/// bureau.
class EcranSimple extends StatelessWidget {
  const EcranSimple({
    required this.titre,
    required this.children,
    super.key,
    this.banniere,
    this.enTete,
  });

  /// Le titre de l'écran, en `titre-ecran`. Le premier élément lu.
  final String titre;

  /// Le corps, empilé sous le titre.
  final List<Widget> children;

  /// Au plus une bannière, pleine largeur, au-dessus du contenu.
  final AppBanner? banniere;

  /// Élément placé entre la bannière et le titre (un retour, par exemple).
  final Widget? enTete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            ?banniere,
            Expanded(
              // Centré quand la place le permet, défilant dès que le clavier
              // ou une grande échelle de texte mange la hauteur : sur un
              // écran de bureau, une colonne de 420 collée en haut laisse un
              // demi-écran de vide.
              child: LayoutBuilder(
                builder: (context, contraintes) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: contraintes.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: marge,
                            vertical: AppSpacing.xl,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              ?enTete,
                              Semantics(
                                header: true,
                                child: Text(
                                  titre,
                                  style: theme.textTheme.headlineMedium,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sousTitre),
                              ...children,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
