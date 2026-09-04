# Locked — version planifiée

Fork de [BuckDenver/Locked](https://github.com/BuckDenver/Locked) (Apache 2.0), avec
ce qui manquait : **des plannings horaires par jour**, et le déverrouillage par
carte NFC comme seule échappatoire.

L'app d'origine savait bloquer des apps à la demande ou pour une durée fixe.
Elle ne savait pas « bloquer tous les jours de 20h à 18h40 ».

## Ce qui a été ajouté

| Fichier | Rôle |
|---|---|
| `Shared/ScheduleRule.swift` | Une règle : profil, jours, heure de début, heure de fin |
| `Shared/ShieldEngine.swift` | Calcule et applique ce qui doit être bloqué maintenant |
| `Shared/ScheduleManager.swift` | Arme les fenêtres DeviceActivity |
| `Shared/SharedStore.swift` | App Group partagé entre l'app et les extensions |
| `Shared/Profile.swift` | Sorti de `ProfileManager` pour être lisible par l'extension |
| `LockedMonitor/` | Nouvelle extension `DeviceActivityMonitor` |
| `Locked/SchedulesView.swift` | Onglet Plannings |
| `Locked/ScheduleEditorView.swift` | Éditeur d'une règle |
| `Locked/ScheduleStore.swift` | Liaison UI ↔ App Group |

## Le principe

**DeviceActivity ne sert que de réveil-matin.** iOS réveille l'extension aux
bornes des fenêtres ; ce qui est réellement bloqué est toujours **recalculé**
par `ShieldEngine` à partir des règles et de l'heure courante, jamais accumulé.

Conséquence : si iOS rate un callback — ça arrive — l'état se corrige tout seul
au prochain réveil ou à la prochaine ouverture de l'app. Un blocage ne peut pas
rester coincé en position ouverte ou fermée.

## Granularité

Chaque règle porte son propre ensemble de jours. Deux règles peuvent viser le
même jour avec des horaires différents, et chaque jour est donc indépendant.

Une plage dont la fin est antérieure au début traverse minuit : `20h00 → 18h40`
signifie « du soir jusqu'au lendemain 18h40 ». La queue du lendemain matin
appartient à la règle de la veille — si seul lundi est coché, le blocage court
du lundi 20h au mardi 18h40, et pas du mardi.

## Déverrouillage NFC

Quand une règle est active, l'onglet Plannings propose *Débloquer avec la carte
NFC*. Le scan doit correspondre au texte écrit sur ta carte. La suspension dure
15 min, 30 min, 1 h ou 2 h selon le réglage, puis le blocage revient tout seul —
même si l'app n'est jamais rouverte, parce qu'une fenêtre DeviceActivity dédiée
réveille l'extension à l'expiration.

Pendant qu'une règle bloque, `denyAppRemoval` empêche de désinstaller Locked.

## Installation

1. `open Locked.xcodeproj`
2. Cible **Locked** → Signing & Capabilities : équipe `NRSS2456MH` (déjà
   renseignée). Vérifier la capability **App Groups** avec
   `group.com.timothee.locked` sur les trois cibles : `Locked`, `LockedShield`,
   `LockedMonitor`. Xcode crée le groupe sur le portail au premier build signé.
3. Brancher l'iPhone, choisir le device, ⌘R.
4. Au lancement, accepter la demande **Temps d'écran / Contrôles familiaux**.
   Sans cette autorisation rien ne peut être bloqué.
5. Onglet **Verrou** → créer la carte NFC (n'importe quel tag NTAG213 à 1 €).
6. Onglet **Plannings** → *Charger ma routine* crée les trois règles :

   | Règle | Jours | Plage |
   |---|---|---|
   | Travail — soir et nuit | tous | 17h45 → 08h00 |
   | Travail — matinée dehors | lun–ven | 10h00 → 13h15 |
   | Loisir écran | tous | 20h00 → 18h40 |

7. Les profils `Travail` et `Loisir` sont créés vides. Il faut y **choisir les
   apps** depuis l'onglet Verrou (appui long sur un profil), sinon les règles
   tournent à vide.

## Limites connues

- **iOS plafonne le nombre de fenêtres surveillées** (20 en pratique). On arme
  donc une fenêtre glissante de 3 jours, ré-armée à chaque bord et à chaque
  ouverture de l'app. Au-delà de 18 fenêtres, les suivantes sont ignorées avec
  un log — visible dans la Console si tu empiles beaucoup de règles.
- **Le texte de la carte est une constante** héritée du projet d'origine
  (`LOCKED-IS-GREAT`). N'importe quel tag portant ce texte débloque. Pour un
  usage perso c'est suffisant ; pour faire mieux il faudrait générer un secret
  aléatoire à la première écriture.
- **Non vérifié** : `denyAppRemoval` empêche la désinstallation, mais rien ne
  dit qu'il empêche de révoquer l'autorisation depuis Réglages → Temps d'écran.
  À tester avant de compter dessus comme d'un verrou absolu.
- **TestFlight demande une approbation Apple** pour Family Controls. Installation
  directe depuis Xcode : pas concerné.
- Family Controls ne fonctionne pas dans le simulateur. L'app s'y lance, mais
  rien ne se bloque : il faut un vrai iPhone.

## Tests

La logique de dates est la partie fragile (traversée de minuit, bascule
dimanche → lundi). Elle ne dépend que de Foundation et se teste hors iOS :

```sh
cp tools/test_rules.swift /tmp/main.swift
swiftc -o /tmp/test_rules Shared/ScheduleRule.swift /tmp/main.swift && /tmp/test_rules
```

41 vérifications, dont les bornes exactes et la cohérence entre `isActive` et
les segments armés.
