# 🧪 test_codexion.sh

*This project has been created as part of the 42 curriculum by mobenais.*

---

## 📋 Description

`test_codexion.sh` est un script de test automatique pour le projet **codexion**.  
Il vérifie la compilation, la gestion des arguments, le comportement des schedulers,
la détection du burnout, l'absence de data races et de fuites mémoire, ainsi que
le format des logs produits par le programme.

Chaque test affiche en temps réel :
- **À gauche** → un spinner avec timer et timeout
- **À droite** → les logs live du programme

---

## 📁 Structure requise

```
votre_projet/
├── Makefile            ← doit contenir une règle 'make re'
├── codexion            ← binaire généré par make
├── test_codexion.sh    ← ce script
└── src/
    └── ...
```

---

## ⚙️ Prérequis

| Outil      | Obligatoire   | Usage                          |
|------------|---------------|--------------------------------|
| `bash`     | ✅            | Exécution du script            |
| `make`     | ✅            | Compilation du projet          |
| `tput`     | ✅            | Affichage spinner / colonnes   |
| `valgrind` | ⚠️ Optionnel  | Tests memcheck + helgrind      |

---

## 🚀 Instructions

### 1. Rendre le script exécutable

```bash
chmod +x test_codexion.sh
```

### 2. Lancer tous les tests

```bash
./test_codexion.sh
```

### 3. Lancer uniquement la compilation

```bash
make re
```

### 4. Lancer le programme manuellement

```bash
./codexion <coders> <burnout> <compile> <debug> <refactor> <cooldown_limit> <cooldown> <scheduler>
```

#### Exemple

```bash
./codexion 3 2000 200 200 200 3 10 fifo
```

---

## 🎯 Arguments du programme

| Position | Argument         | Type    | Description                                 | Exemple  |
|----------|------------------|---------|---------------------------------------------|----------|
| 1        | `coders`         | entier  | Nombre de coders (threads)                  | `3`      |
| 2        | `burnout`        | entier  | Temps avant burnout (ms)                    | `2000`   |
| 3        | `compile`        | entier  | Durée d'une compilation (ms)                | `200`    |
| 4        | `debug`          | entier  | Durée d'un debug (ms)                       | `200`    |
| 5        | `refactor`       | entier  | Durée d'un refactor (ms)                    | `200`    |
| 6        | `cooldown_limit` | entier  | Nombre de cycles avant cooldown obligatoire | `3`      |
| 7        | `cooldown`       | entier  | Durée du cooldown (ms)                      | `10`     |
| 8        | `scheduler`      | string  | Algorithme de scheduling : `fifo` ou `edf`  | `fifo`   |

### Arguments invalides rejetés

| Cas                     | Exemple                                            |
|-------------------------|----------------------------------------------------|
| Aucun argument          | `./codexion`                                       |
| Trop peu d'arguments    | `./codexion 3 2000`                                |
| Scheduler inconnu       | `./codexion 3 2000 200 200 200 3 10 sjf`           |
| Coders négatifs         | `./codexion -1 2000 200 200 200 3 10 fifo`         |
| Burnout négatif         | `./codexion 3 -1 200 200 200 3 10 fifo`            |
| Cooldown négatif        | `./codexion 3 2000 200 200 200 3 -1 fifo`          |

---

## 🧩 Sections de tests

| Section | Nom                      | Description                                                        |
|---------|--------------------------|--------------------------------------------------------------------|
| `0`     | Compilation              | `make re` — vérifie que le projet compile                          |
| `1`     | Arguments invalides      | Rejette correctement les mauvais arguments                         |
| `2`     | Cas 1 coder              | Burnout détecté avec un seul coder                                 |
| `3`     | FIFO — cas normaux       | 2 / 3 / 5 / 10 coders avec scheduler FIFO                         |
| `4`     | EDF — cas normaux        | 2 / 3 / 5 / 10 coders avec scheduler EDF                          |
| `5`     | Burnout                  | Vérifie que le burnout arrive au bon moment                        |
| `6`     | Stress test              | 20 coders simultanés sans crash                                    |
| `7`     | Répétabilité             | 5 runs successifs sans deadlock                                    |
| `8`     | Valgrind memcheck        | Zéro fuite mémoire *(si valgrind installé)*                        |
| `9`     | Helgrind                 | Zéro data race *(si valgrind installé)*                            |
| `10`    | Format des logs          | Format strict + timestamps croissants                              |

---

## 📺 Affichage en temps réel

Pendant chaque test, le terminal affiche simultanément :

```
⠹ 3s/15s (-12s)              42 1 has taken a dongle
                              42 2 is compiling
                              42 1 is debugging
                              42 2 burned out
```

| Zone       | Contenu                                              |
|------------|------------------------------------------------------|
| **Gauche** | Spinner animé + temps écoulé + temps restant         |
| **Droite** | Logs live produits par `./codexion` en temps réel    |

> Si le timer atteint `0s` → le test est marqué **[KO] timeout** → deadlock probable.

---

## ✅ Format de sortie attendu

Chaque ligne produite par le programme doit respecter **exactement** ce format :

```
<timestamp_ms> <coder_id> <action>
```

### Actions valides

| Action                 |
|------------------------|
| `has taken a dongle`   |
| `is compiling`         |
| `is debugging`         |
| `is refactoring`       |
| `burned out`           |

### Exemple de sortie correcte

```
0 1 has taken a dongle
0 2 has taken a dongle
200 1 is compiling
200 2 is debugging
400 1 is refactoring
600 2 burned out
```

---

## 📊 Résumé final

À la fin du script, un résumé s'affiche :

```
══════════════════════════════════════════
  RÉSUMÉ
══════════════════════════════════════════
Total : 32 | OK : 30 | KO : 2

✗ 2 test(s) échoué(s)
```

### Codes de retour

| Code | Signification          |
|------|------------------------|
| `0`  | Tous les tests passent |
| `1`  | Au moins un test KO    |

---

## 🐛 Erreurs courantes

| Erreur observée                          | Cause probable                               |
|------------------------------------------|----------------------------------------------|
| `timeout (deadlock?)`                    | Mutex non libéré / attente infinie           |
| `lignes mal formatées`                   | `printf` avec mauvais format                 |
| `timestamps non croissants`              | Race condition sur le timestamp              |
| `burnout non détecté`                    | Condition de burnout jamais vérifiée         |
| `X erreurs Helgrind`                     | Accès concurrent non protégé                |
| `X erreurs mémoire`                      | `malloc` sans `free` / use-after-free        |
| `Compilation échouée`                    | Erreur de code — voir `/tmp/compile_err.txt` |

---

## 🔧 Personnalisation

Pour modifier les timeouts ou les arguments de test, édite directement le script :

```bash
# Augmenter le timeout du stress test (section 6)
test_normal "Stress / 20 coders / fifo" "20 3000 100 100 100 3 10 fifo" 60
#                                                                        ^^
#                                                                 timeout en secondes
```

---

## 📝 Notes

- Les tests **Valgrind** sont automatiquement ignorés si `valgrind` n'est pas installé
- Le script **s'arrête immédiatement** si la compilation échoue (section 0)
- Le fichier `/tmp/compile_err.txt` contient les erreurs de compilation en cas d'échec
- Les fichiers temporaires `/tmp/spinner_fifo_*` et `/tmp/spinner_out.txt` sont nettoyés automatiquement après chaque test

---

## 👤 Auteur

| Login    | École |
|----------|-------|
| mobenais | 42    |