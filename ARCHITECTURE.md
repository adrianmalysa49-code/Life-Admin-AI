# Life Admin AI — Architektura Projektu

## Stack
- **Frontend**: Next.js 15 (App Router) + TypeScript + TailwindCSS
- **Backend**: Next.js API Routes (Node.js runtime)
- **Database**: PostgreSQL (Supabase)
- **Auth**: Clerk
- **AI**: Anthropic Claude API (claude-sonnet-4-20250514)
- **Storage**: Supabase Storage (szyfrowane buckety)
- **OCR**: Tesseract.js (client-side) + Google Vision API (server-side fallback)
- **Email**: Resend (powiadomienia)
- **Hosting**: Vercel

---

## Struktura Folderów

```
life-admin-ai/
├── app/                              # Next.js App Router
│   ├── (auth)/                       # Clerk auth pages
│   │   ├── sign-in/[[...sign-in]]/
│   │   └── sign-up/[[...sign-up]]/
│   ├── (dashboard)/                  # Chronione routy
│   │   ├── layout.tsx                # Dashboard layout + sidebar
│   │   ├── page.tsx                  # Dashboard główny
│   │   ├── documents/
│   │   │   ├── page.tsx              # Vault — lista dokumentów
│   │   │   ├── upload/page.tsx       # Upload + OCR
│   │   │   └── [id]/page.tsx         # Szczegóły dokumentu
│   │   ├── analyzer/
│   │   │   └── [id]/page.tsx         # AI analiza dokumentu
│   │   ├── letters/
│   │   │   ├── page.tsx              # Lista pism
│   │   │   └── new/page.tsx          # Generator pism AI
│   │   ├── deadlines/
│   │   │   └── page.tsx              # Kalendarz terminów
│   │   ├── bills/
│   │   │   └── page.tsx              # Organizator rachunków
│   │   ├── assistant/
│   │   │   └── page.tsx              # Government Assistant
│   │   └── settings/
│   │       └── page.tsx
│   ├── api/
│   │   ├── webhooks/
│   │   │   └── clerk/route.ts        # Clerk user sync
│   │   ├── documents/
│   │   │   ├── route.ts              # GET list, POST upload
│   │   │   └── [id]/
│   │   │       ├── route.ts          # GET, DELETE
│   │   │       └── analyze/route.ts  # POST AI analiza
│   │   ├── ocr/
│   │   │   └── route.ts              # POST OCR processing
│   │   ├── letters/
│   │   │   ├── route.ts              # GET list, POST generate
│   │   │   └── [id]/route.ts
│   │   ├── deadlines/
│   │   │   └── route.ts
│   │   ├── bills/
│   │   │   └── route.ts
│   │   ├── assistant/
│   │   │   └── route.ts              # Government workflow AI
│   │   ├── search/
│   │   │   └── route.ts              # Full-text search
│   │   └── billing/
│   │       ├── checkout/route.ts
│   │       └── webhook/route.ts
│   ├── layout.tsx
│   └── globals.css
│
├── components/
│   ├── ui/                           # Shadcn/ui + custom
│   │   ├── button.tsx
│   │   ├── card.tsx
│   │   ├── badge.tsx
│   │   ├── dialog.tsx
│   │   ├── input.tsx
│   │   └── ...
│   ├── dashboard/
│   │   ├── Sidebar.tsx
│   │   ├── TopBar.tsx
│   │   ├── StatsCard.tsx
│   │   └── ActivityFeed.tsx
│   ├── documents/
│   │   ├── DocumentCard.tsx
│   │   ├── DocumentUploader.tsx      # Drag & drop + OCR progress
│   │   ├── DocumentAnalysis.tsx      # AI wyniki
│   │   └── DocumentVault.tsx
│   ├── letters/
│   │   ├── LetterGenerator.tsx
│   │   └── LetterPreview.tsx
│   ├── deadlines/
│   │   ├── DeadlineCalendar.tsx
│   │   └── DeadlineCard.tsx
│   ├── bills/
│   │   └── BillTracker.tsx
│   └── assistant/
│       └── GovernmentAssistant.tsx
│
├── lib/
│   ├── db/
│   │   ├── index.ts                  # DB connection pool
│   │   ├── queries/                  # SQL query functions
│   │   │   ├── documents.ts
│   │   │   ├── letters.ts
│   │   │   ├── deadlines.ts
│   │   │   └── users.ts
│   │   └── migrations/               # SQL migration files
│   │       ├── 001_initial_schema.sql
│   │       ├── 002_add_audit_logs.sql
│   │       └── 003_add_fts.sql
│   ├── ai/
│   │   ├── client.ts                 # Anthropic client singleton
│   │   ├── prompts/
│   │   │   ├── analyzer.ts           # Document analysis prompts
│   │   │   ├── letterGenerator.ts    # Letter generation prompts
│   │   │   └── assistant.ts          # Government assistant prompts
│   │   └── parsers.ts                # Parse structured AI responses
│   ├── ocr/
│   │   ├── tesseract.ts
│   │   └── googleVision.ts
│   ├── storage/
│   │   └── supabase.ts               # Signed URLs, upload, delete
│   ├── encryption/
│   │   └── index.ts                  # AES-256 document encryption
│   ├── notifications/
│   │   └── resend.ts                 # Email templates + sending
│   ├── billing/
│   │   └── stripe.ts
│   ├── auth/
│   │   └── helpers.ts                # Clerk + DB user helpers
│   ├── rateLimit/
│   │   └── index.ts                  # Upstash Redis rate limiting
│   └── utils.ts
│
├── hooks/
│   ├── useDocuments.ts
│   ├── useDeadlines.ts
│   └── useUpload.ts
│
├── types/
│   ├── document.ts
│   ├── letter.ts
│   ├── deadline.ts
│   └── api.ts
│
├── middleware.ts                      # Clerk auth middleware
├── next.config.ts
├── tailwind.config.ts
├── tsconfig.json
└── .env.example
```

---

## Role Użytkowników

| Rola | Limit dokumentów | AI analizy/mies | Generowanie pism | Powiadomienia |
|------|-----------------|-----------------|-----------------|---------------|
| `free` | 10 | 5 | 3 | email tylko |
| `premium` | unlimited | unlimited | unlimited | email + push |
| `admin` | — | — | — | full access |

---

## Przepływ Danych (Pipeline)

```
[Upload plik] 
    → Supabase Storage (zaszyfrowany)
    → OCR (Tesseract/Vision) → raw_text
    → Claude: detect_type + extract_metadata
    → PostgreSQL: document record + deadlines + tags
    → Cron job: sprawdź terminy → Resend email
```

---

## Bezpieczeństwo

1. **Szyfrowanie**: AES-256-GCM dla plików przed uploadem do Storage
2. **RLS**: Row Level Security w Supabase (user_id check)
3. **Auth**: Clerk JWT weryfikowany w każdym API route
4. **Rate limiting**: Upstash Redis (np. 100 req/15min per user)
5. **Audit logs**: każda akcja na dokumencie logowana
6. **Signed URLs**: dostęp do plików tylko przez 15-minutowe tokeny
