#!/bin/bash
set -e

REPO="multiagents-fer/multiagents-projects"

echo "=========================================="
echo " Creating labels for $REPO"
echo "=========================================="

# Type labels
gh label create "epic" --repo "$REPO" --color "6A0DAD" --description "Epic - Large feature group" --force
gh label create "user-story" --repo "$REPO" --color "0075CA" --description "User Story - Deliverable feature" --force
gh label create "task" --repo "$REPO" --color "A2EEEF" --description "Task - Implementation unit" --force

# Area labels
gh label create "backend" --repo "$REPO" --color "D93F0B" --description "Backend - Flask API (proj-back-marketplace)" --force
gh label create "frontend" --repo "$REPO" --color "0E8A16" --description "Frontend - Angular 18 (proj-front-marketplace)" --force
gh label create "integration" --repo "$REPO" --color "FBCA04" --description "Integration - External services & adapters" --force
gh label create "infrastructure" --repo "$REPO" --color "5319E7" --description "Infrastructure - AWS, Terraform, CI/CD" --force
gh label create "design" --repo "$REPO" --color "F9D0C4" --description "Design - UX/UI design work" --force
gh label create "database" --repo "$REPO" --color "BFD4F2" --description "Database - Schema, migrations, queries" --force

# Priority labels
gh label create "priority-critical" --repo "$REPO" --color "B60205" --description "Priority: Critical - Must have for MVP" --force
gh label create "priority-high" --repo "$REPO" --color "D93F0B" --description "Priority: High - Important for launch" --force
gh label create "priority-medium" --repo "$REPO" --color "FBCA04" --description "Priority: Medium - Nice to have" --force
gh label create "priority-low" --repo "$REPO" --color "0E8A16" --description "Priority: Low - Future enhancement" --force

# Sprint labels
gh label create "sprint-1" --repo "$REPO" --color "C5DEF5" --description "Sprint 1 - Foundation & Setup" --force
gh label create "sprint-2" --repo "$REPO" --color "C5DEF5" --description "Sprint 2 - Auth & Catalog Base" --force
gh label create "sprint-3" --repo "$REPO" --color "C5DEF5" --description "Sprint 3 - Catalog & Reports" --force
gh label create "sprint-4" --repo "$REPO" --color "C5DEF5" --description "Sprint 4 - Purchase Flow" --force
gh label create "sprint-5" --repo "$REPO" --color "C5DEF5" --description "Sprint 5 - KYC & Financing" --force
gh label create "sprint-6" --repo "$REPO" --color "C5DEF5" --description "Sprint 6 - Insurance & Financing" --force
gh label create "sprint-7" --repo "$REPO" --color "C5DEF5" --description "Sprint 7 - Admin & Notifications" --force
gh label create "sprint-8" --repo "$REPO" --color "C5DEF5" --description "Sprint 8 - SEO, Polish & Launch" --force

# Module labels
gh label create "mod-vehicles" --repo "$REPO" --color "E4E669" --description "Module: Vehicle catalog & search" --force
gh label create "mod-auth" --repo "$REPO" --color "E4E669" --description "Module: Authentication & users" --force
gh label create "mod-purchase" --repo "$REPO" --color "E4E669" --description "Module: Purchase flow" --force
gh label create "mod-kyc" --repo "$REPO" --color "E4E669" --description "Module: KYC identity verification" --force
gh label create "mod-financing" --repo "$REPO" --color "E4E669" --description "Module: Credit & financing" --force
gh label create "mod-insurance" --repo "$REPO" --color "E4E669" --description "Module: Insurance marketplace" --force
gh label create "mod-admin" --repo "$REPO" --color "E4E669" --description "Module: Admin panel" --force
gh label create "mod-notifications" --repo "$REPO" --color "E4E669" --description "Module: Notifications & chat" --force
gh label create "mod-market" --repo "$REPO" --color "E4E669" --description "Module: Market analytics" --force

# Status labels
gh label create "ready-for-dev" --repo "$REPO" --color "0E8A16" --description "Ready for AI/dev to pick up" --force
gh label create "blocked" --repo "$REPO" --color "B60205" --description "Blocked by dependency" --force
gh label create "needs-design" --repo "$REPO" --color "F9D0C4" --description "Needs UX/UI design first" --force
gh label create "needs-review" --repo "$REPO" --color "FBCA04" --description "Needs review/refinement" --force

echo ""
echo "All labels created successfully!"
echo "=========================================="
