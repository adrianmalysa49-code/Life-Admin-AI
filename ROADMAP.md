# Life Admin AI — Roadmapa Developmentu

## ETAP 1 — Fundament (OBECNY) ✅
- [x] Architektura projektu
- [x] Schemat bazy danych (PostgreSQL)
- [x] Konfiguracja (next.config, tsconfig, env)
- [x] Typy TypeScript
- [x] DB connection pool
- [x] Rate limiting (Upstash)
- [x] Audit logging
- [x] Szyfrowanie (AES-256-GCM)
- [x] Supabase Storage helper
- [x] Middleware Clerk

---

## ETAP 2 — Auth + Layout + Dashboard
- [ ] Clerk webhooks → sync user do DB
- [ ] Root layout + fonts + globals.css
- [ ] Dashboard layout (Sidebar + TopBar)
- [ ] Dashboard główny (stats, aktywność)
- [ ] Onboarding flow (nowy użytkownik)

---

## ETAP 3 — Document Upload + OCR
- [ ] DocumentUploader component (drag & drop)
- [ ] POST /api/ocr (Tesseract.js server-side)
- [ ] POST /api/documents (upload + zapis w DB)
- [ ] Pipeline: upload → szyfrowanie → storage → OCR → zapis
- [ ] Document Vault (lista z filtrami)
- [ ] Document card component

---

## ETAP 4 — AI Analyzer
- [ ] Anthropic client + prompts
- [ ] POST /api/documents/[id]/analyze
- [ ] Auto-detect type dokumentu
- [ ] Ekstrakcja: terminy, kwoty, akcje, ryzyka
- [ ] DocumentAnalysis component (wyniki AI)
- [ ] Auto-tworzenie Deadline przy wykryciu terminu

---

## ETAP 5 — Deadline Tracker
- [ ] GET/POST/PATCH /api/deadlines
- [ ] DeadlineCalendar component
- [ ] DeadlineCard z priorytetem
- [ ] Cron job: mark_overdue_deadlines (Vercel Cron)
- [ ] Email powiadomienia (Resend)

---

## ETAP 6 — Letter Generator
- [ ] POST /api/letters (generowanie AI)
- [ ] LetterGenerator form + preview
- [ ] Szablony: reklamacja, odwołanie, wypowiedzenie, wniosek
- [ ] Export do PDF/DOCX
- [ ] Historia pism

---

## ETAP 7 — Bill Organizer
- [ ] GET/POST/PATCH /api/bills
- [ ] BillTracker component
- [ ] Historia płatności
- [ ] Przypomnienia o płatnościach

---

## ETAP 8 — Government Assistant
- [ ] POST /api/assistant (streaming AI)
- [ ] Chat UI z workflow
- [ ] Baza wiedzy: polskie urzędy, formularze
- [ ] Generowanie checklist

---

## ETAP 9 — Search + Vault
- [ ] GET /api/search (FTS PostgreSQL)
- [ ] SearchBar component
- [ ] Filtrowanie po typie, tagach, dacie
- [ ] Bulk operations (archive, delete)

---

## ETAP 10 — Billing + Premium
- [ ] Stripe checkout (Stripe)
- [ ] POST /api/billing/webhook
- [ ] Paywall components (usage limits)
- [ ] Pricing page
- [ ] Settings + plan management

---

## ETAP 11 — Polish + Production
- [ ] Mobile responsiveness
- [ ] Loading states + skeletons
- [ ] Error boundaries
- [ ] Monitoring (Sentry)
- [ ] Performance audit
- [ ] Security audit
- [ ] GDPR compliance

---

## Timeline szacunkowy
| Etap | Czas |
|------|------|
| 1-2  | 2 dni |
| 3-4  | 3 dni |
| 5-6  | 2 dni |
| 7-8  | 2 dni |
| 9-10 | 2 dni |
| 11   | 2 dni |
| **MVP** | **~2 tygodnie** |
