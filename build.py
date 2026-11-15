"""Builds the Claude version of the lab from the GitHub Copilot version.

index.html is the single source. This script writes claude.html (same page, Claude Code wording in the
few places where the tool matters) and fichiers/CLAUDE.md (same context file under the name Claude Code
reads). Every replacement must match exactly, so an edit to index.html that breaks one fails loudly
instead of shipping a half-converted page.
Run after any change to index.html or fichiers/copilot-instructions.md:  python build.py
"""
from __future__ import annotations

import pathlib
import shutil
import sys

sys.stdout.reconfigure(encoding="utf-8")

HERE = pathlib.Path(__file__).parent

STEP3_OLD_START = '<ol class="steps">\n    <li>Créez un dossier <b>hors de tout dépôt git</b>'
STEP3_OLD_END = "<li>Collez ce prompt et envoyez :</li>\n  </ol>"
STEP3_NEW = """<ol class="steps">
    <li>Créez un dossier (par exemple <code>C:\\lab-accueil</code>) et mettez-y <a href="fichiers/CLAUDE.md" download><code>CLAUDE.md</code></a> à la racine (le fichier complété à l'étape 2). Claude Code le lit au début de chaque session.</li>
    <li>Ouvrez un terminal et connectez-vous : <code>az login --tenant VOTRE_TENANT_ID</code>.</li>
    <li>Ouvrez une <b>nouvelle session</b> Claude Code sur ce dossier : dans l'application de bureau Claude, onglet <b>Code</b>, choisissez le dossier ; ou dans un terminal, <code>cd C:\\lab-accueil</code> puis <code>claude</code>.</li>
    <li>Collez ce prompt et envoyez :</li>
  </ol>"""

# (old, new, expected count)
REPLACEMENTS = [
    ("<title>Lab : construisons un agent ensemble</title>", "<title>Lab : construisons un agent ensemble, avec Claude</title>", 1),
    ("un workflow Copilot Studio écrit par GitHub Copilot et créé avec Azure CLI", "un workflow Copilot Studio écrit par Claude et créé avec Azure CLI", 1),
    ("Un workflow Copilot Studio écrit par GitHub Copilot, puis", "Un workflow Copilot Studio écrit par Claude, puis", 1),
    ('<a href="./" class="on" aria-current="page">🤖 GitHub Copilot</a><a href="claude.html">✦ Claude</a>',
     '<a href="./">🤖 GitHub Copilot</a><a href="claude.html" class="on" aria-current="page">✦ Claude</a>', 1),
    ("un workflow écrit par GitHub Copilot", "un workflow écrit par Claude", 2),
    ("<i>🤖</i>GitHub Copilot</div>", "<i>✦</i>Claude Code</div>", 1),
    ("Écrit par <b>GitHub Copilot</b> à partir", "Écrit par <b>Claude</b> (Claude Code) à partir", 1),
    ('src="images/comment-on-va-le-construire.png"', 'src="images/comment-on-va-le-construire-claude.png"', 1),
    ("un fichier de contexte, GitHub Copilot écrit le workflow", "un fichier de contexte, Claude écrit le workflow", 1),
    ("<li>GitHub Copilot : l'application de bureau ou la ligne de commande, avec un abonnement actif.</li>",
     "<li>Claude Code : dans l'application de bureau Claude (onglet Code) ou en ligne de commande (<code>claude</code>), avec un abonnement Claude payant ou un compte de la console Anthropic : <a href=\"https://code.claude.com/docs/en/overview\" target=\"_blank\" rel=\"noopener\">installer Claude Code</a>.</li>", 1),
    ('<a href="fichiers/copilot-instructions.md" download><span class="big">🧭</span><b>copilot-instructions.md</b><span>Le contexte pour GitHub Copilot',
     '<a href="fichiers/CLAUDE.md" download><span class="big">🧭</span><b>CLAUDE.md</b><span>Le contexte pour Claude Code', 1),
    ("GitHub Copilot créera lui-même les trois", "Claude créera lui-même les trois", 1),
    ("la page remplace les repères dans <code>copilot-instructions.md</code>", "la page remplace les repères dans <code>CLAUDE.md</code>", 1),
    ("Télécharger mon copilot-instructions.md", "Télécharger mon CLAUDE.md", 1),
    ("<h2><span class=\"num\">3</span>Le workflow, écrit par GitHub Copilot</h2>", "<h2><span class=\"num\">3</span>Le workflow, écrit par Claude</h2>", 1),
    ("dont quelques minutes où Copilot travaille seul", "dont quelques minutes où Claude travaille seul", 1),
    ('data-label="Le prompt, à coller dans GitHub Copilot"', 'data-label="Le prompt, à coller dans Claude Code"', 1),
    ('<b>Vous préférez Claude ?</b> Le même lab existe avec Claude Code : <a href="claude.html#etape3">ouvrir la version Claude</a>.',
     '<b>Vous préférez GitHub Copilot ?</b> Le même lab existe avec GitHub Copilot : <a href="./#etape3">ouvrir la version GitHub Copilot</a>.', 1),
    ("<b>Ce qui doit se passer :</b> Copilot lit le fichier de contexte",
     "<b>Ce qui doit se passer :</b> Claude lit le fichier de contexte", 1),
    ("Quelques minutes, sans question.</div>",
     "Quelques minutes, sans question.</div>\n  <div class=\"callout note\"><b>Claude Code demande votre accord</b> avant de lancer une commande ou d'écrire un fichier : lisez et acceptez. Vous pouvez autoriser <code>az</code> pour le reste de la session.</div>", 1),
    ("le fichier de contexte donne à Copilot les règles exactes", "le fichier de contexte donne à Claude les règles exactes", 1),
    ("Dites à Copilot que la ligne est ajoutée", "Dites à Claude que la ligne est ajoutée", 1),
    ("<b>Si Copilot hésite ou cherche sur le web</b> : rappelez-lui que tout est dans <code>copilot-instructions.md</code>.",
     "<b>Si Claude hésite ou cherche sur le web</b> : rappelez-lui que tout est dans <code>CLAUDE.md</code>.", 1),
    ('<li><a href="https://docs.github.com/copilot" target="_blank" rel="noopener">Documentation GitHub Copilot</a></li>',
     '<li><a href="https://code.claude.com/docs/en/overview" target="_blank" rel="noopener">Documentation Claude Code</a></li>', 1),
    ("fetch('fichiers/copilot-instructions.md'", "fetch('fichiers/CLAUDE.md'", 1),
    ("a.download = 'copilot-instructions.md';", "a.download = 'CLAUDE.md';", 1),
    ("toast('Votre fichier est prêt : mettez-le dans .github\\\\');", "toast('Votre fichier est prêt : mettez-le à la racine du dossier');", 1),
]


def main() -> None:
    src = (HERE / "index.html").read_text(encoding="utf-8")
    s = src
    i, j = s.find(STEP3_OLD_START), s.find(STEP3_OLD_END)
    if i < 0 or j < 0:
        raise SystemExit("step 3 block not found in index.html")
    s = s[:i] + STEP3_NEW + s[j + len(STEP3_OLD_END):]
    for old, new, count in REPLACEMENTS:
        found = s.count(old)
        if found != count:
            raise SystemExit(f"expected {count} x {old[:70]!r}, found {found}")
        s = s.replace(old, new)
    (HERE / "claude.html").write_text(s, encoding="utf-8")
    shutil.copyfile(HERE / "fichiers" / "copilot-instructions.md", HERE / "fichiers" / "CLAUDE.md")
    left = [line.strip()[:90] for line in s.splitlines() if "GitHub Copilot" in line]
    print("claude.html written,", len(s), "chars; lines still naming GitHub Copilot:")
    for line in left:
        print("  ", line)


if __name__ == "__main__":
    main()
