#!/bin/bash
# ============================================
# AgentsMX Skills Installer
# Instala todas las skills de Claude Code
# ============================================
set -e

SKILLS_DIR="$HOME/.claude/skills"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo " AgentsMX Skills Installer"
echo " Target: $SKILLS_DIR"
echo "============================================"
echo ""

# Create base directory
mkdir -p "$SKILLS_DIR"

# Install each skill
for skill_dir in "$SCRIPT_DIR"/expert-*/; do
  skill_name=$(basename "$skill_dir")
  echo "  Installing: $skill_name"
  mkdir -p "$SKILLS_DIR/$skill_name"
  cp "$skill_dir/SKILL.md" "$SKILLS_DIR/$skill_name/SKILL.md"
done

echo ""
echo "============================================"
echo " 8 skills installed successfully!"
echo "============================================"
echo ""
echo " Available commands in Claude Code:"
echo "   /expert-angular"
echo "   /expert-aws"
echo "   /expert-flask"
echo "   /expert-product-owner"
echo "   /expert-python"
echo "   /expert-software-architect"
echo "   /expert-used-car-business"
echo "   /expert-ux-ui"
echo ""
echo " Skills are global (available in all projects)"
echo "============================================"
