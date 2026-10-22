<p align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Logo EpiValastor">
</p>

<h1 align="center">EpiValastor pour Mac, iPhone et iPad</h1>

<p align="center">
  Ton emploi du temps (Zeus, Hyperplanning… via un lien <b>ICS</b>) toujours sous les yeux :<br>
  planning, temps restant, examens, changements de dernière minute.<br>
  Version Android : <a href="https://github.com/Valastored/epivalastor-android">epivalastor-android</a>
</p>

---

## ⬇️ Télécharger

Va dans **[Releases](../../releases/latest)** et télécharge :

| Appareil | Fichier |
|---|---|
| 💻 Mac (macOS 14 Sonoma ou plus récent) | `EpiValastor-macOS.zip` |
| 📱 iPhone / iPad (iOS 17 ou plus récent) | `EpiValastor.ipa` |

---

## 💻 Installer sur Mac

1. Télécharge `EpiValastor-macOS.zip` et double-clique dessus pour le décompresser.
2. Glisse **EpiValastor.app** dans le dossier **Applications**.
3. **Premier lancement** : l'app n'est pas vérifiée par Apple (elle n'est pas sur l'App Store), macOS va la bloquer.
   - Fais **clic droit sur EpiValastor › Ouvrir**, puis **Ouvrir** dans la fenêtre qui s'affiche ;
   - si ça ne suffit pas : **Réglages Système › Confidentialité et sécurité**, en bas : **« Ouvrir quand même »**.
4. Ajoute ton lien ICS : menu **EpiValastor › Réglages… (⌘,) › Agendas**.
5. Widget : clic droit sur le bureau › **Modifier les widgets** › EpiValastor.

## 📱 Installer sur iPhone / iPad

Apple n'autorise pas l'installation d'un fichier comme un APK Android. Le plus simple et **gratuit** :
**[SideStore](https://sidestore.io)** (ou **[AltStore](https://altstore.io)**), qui installe l'app avec ton identifiant Apple
et la **renouvelle automatiquement** tous les 7 jours.

1. Installe **SideStore** sur ton iPhone en suivant [le guide officiel](https://docs.sidestore.io) (à faire une seule fois, avec un ordinateur).
2. Télécharge `EpiValastor.ipa` sur ton iPhone (Safari › Releases, ou AirDrop depuis ton ordinateur).
3. Ouvre **SideStore › My Apps › +** et choisis `EpiValastor.ipa`.
4. Ouvre EpiValastor › ⚙️ **Réglages › Agendas** › ajoute ton lien ICS.
5. Autorise les **notifications** et les **Live Activities** quand l'app le demande.

> Limites d'un compte Apple gratuit : 3 apps « sideloadées » maximum, renouvellement tous les 7 jours (SideStore le fait tout seul).

---

## 🔗 Où trouver ton lien ICS ?

Dans ton outil d'emploi du temps (ex. **Zeus** pour l'EPITA / IONIS), cherche **Exporter / iCal / S'abonner** sur la vue de ton groupe
et copie le lien (`https://…ics…`). ⚠️ Ce lien est personnel : ne le partage pas publiquement.

---

## ✨ Fonctionnalités

- **Planning semaine / jour** : un bloc par jour avec horaires de début–fin, pauses, ligne rouge de progression.
- **Examens** (partiel, QCM, contrôle, soutenance…) en rouge, **fériés / vacances** en bleu-vert.
- **Prochain cours** toujours visible, avec le temps restant.
- **Changements détectés** à chaque synchro (cours ajouté, annulé, déplacé).
- **Recherche** par matière, prof ou salle · **mini-calendrier** · **statistiques** (heures par matière, avancement…).
- **Mac** : barre des menus (cours + compte à rebours), widgets du bureau.
- **iPhone / iPad** : **Live Activity** (écran verrouillé + Dynamic Island), widgets écran d'accueil et écran verrouillé,
  notifications (rappel 5–60 min avant, examens la veille à 19 h, changements), synchro en arrière-plan.
- Thème **Système / Clair / Sombre**, matières masquables, plusieurs agendas avec couleurs.

---

## 🛠️ Compiler depuis le code

Prérequis : un Mac avec **Xcode 15+**.

```bash
git clone https://github.com/Valastored/epivalastor-apple.git
open epivalastor-apple/EpiValastor.xcodeproj
```

1. Dans chaque cible (**EpiValastor**, **EpiValastorWidget**, **EpiValastoriOS**, **EpiValastoriOSWidget**) :
   *Signing & Capabilities › Team* → choisis **ton** compte Apple.
2. **Mac** : schéma `EpiValastor`, destination *My Mac*, ▶.
3. **iPhone** : schéma `EpiValastoriOS`, branche ton iPhone (Mode développeur activé), ▶.
4. **Générer l'IPA** : schéma `EpiValastoriOS`, destination *Any iOS Device*, **Product › Archive**, puis dans l'archive :
   `Products/Applications/EpiValastoriOS.app` → place-le dans un dossier `Payload/` et compresse-le en `EpiValastor.ipa`.

### Organisation du code

| Dossier | Contenu |
|---|---|
| `Shared/` | Modèles, lecteur ICS, règles (examens, fériés), stockage partagé — commun à tout |
| `App/` | App Mac + logique de synchro et vues du planning (réutilisées par l'iPhone) |
| `iOS/` | App iPhone / iPad : écran principal, réglages, notifications, Live Activity |
| `Widget/` | Widgets (Mac et iPhone) |
| `WidgetiOS/` | Live Activity (Dynamic Island) |

---

<p align="center">Développé par <b>Valastor</b></p>
