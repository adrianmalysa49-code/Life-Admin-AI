// app/(dashboard)/page.tsx
import { auth, currentUser } from '@clerk/nextjs/server'
import { redirect } from 'next/navigation'
import {
  FileStack, Calendar, CreditCard, ScrollText,
  AlertTriangle, Upload, Sparkles
} from 'lucide-react'
import TopBar from '@/components/dashboard/TopBar'
import StatsCard from '@/components/dashboard/StatsCard'
import ActivityFeed from '@/components/dashboard/ActivityFeed'
import UrgentDeadlines from '@/components/dashboard/UrgentDeadlines'
import QuickActions from '@/components/dashboard/QuickActions'
import { getUserByClerkId, queryOne, query } from '@/lib/db'
import type { Deadline, UserStats } from '@/types'

async function getDashboardData(userId: string) {
  const [stats, deadlines, activity] = await Promise.all([
    // Stats
    queryOne<UserStats>(
      `SELECT
         COUNT(DISTINCT doc.id) FILTER (WHERE doc.status='active')::int AS total_documents,
         COUNT(DISTINCT dl.id)  FILTER (WHERE dl.status='pending')::int AS pending_deadlines,
         COUNT(DISTINCT dl.id)  FILTER (
           WHERE dl.status='pending' AND dl.due_date <= NOW() + INTERVAL '7 days'
         )::int AS urgent_deadlines,
         COUNT(DISTINCT b.id) FILTER (WHERE b.status='active')::int AS active_bills,
         COUNT(DISTINCT l.id)::int AS total_letters
       FROM users u
       LEFT JOIN documents doc ON doc.user_id = u.id
       LEFT JOIN deadlines dl  ON dl.user_id  = u.id
       LEFT JOIN bills b       ON b.user_id   = u.id
       LEFT JOIN letters l     ON l.user_id   = u.id
       WHERE u.id = $1 GROUP BY u.id`,
      [userId]
    ),
    // Urgent deadlines (next 30 days + overdue)
    query<Deadline>(
      `SELECT * FROM deadlines
       WHERE user_id = $1
         AND status = 'pending'
         AND due_date <= NOW() + INTERVAL '30 days'
       ORDER BY due_date ASC LIMIT 5`,
      [userId]
    ),
    // Recent activity
    query<{ type: string; id: string; title: string; action: string; created_at: string }>(
      `(SELECT 'document' AS type, id::text, original_name AS title, 'upload' AS action, created_at
        FROM documents WHERE user_id = $1 AND status='active')
       UNION ALL
       (SELECT 'letter', id::text, title, 'generated', created_at
        FROM letters WHERE user_id = $1)
       UNION ALL
       (SELECT 'deadline', id::text, title, 'added', created_at
        FROM deadlines WHERE user_id = $1)
       ORDER BY created_at DESC LIMIT 8`,
      [userId]
    ),
  ])

  return { stats, deadlines, activity }
}

export default async function DashboardPage() {
  const { userId: clerkId } = await auth()
  if (!clerkId) redirect('/sign-in')

  const [clerkUser, dbUser] = await Promise.all([
    currentUser(),
    getUserByClerkId(clerkId),
  ])

  if (!dbUser) redirect('/sign-in')

  const { stats, deadlines, activity } = await getDashboardData(dbUser.id)

  const s = stats ?? {
    total_documents: 0,
    pending_deadlines: 0,
    urgent_deadlines: 0,
    active_bills: 0,
    total_letters: 0,
  }

  const firstName = clerkUser?.firstName ?? 'Użytkowniku'
  const hour = new Date().getHours()
  const greeting =
    hour < 12 ? 'Dzień dobry' : hour < 18 ? 'Cześć' : 'Dobry wieczór'

  return (
    <>
      <TopBar
        title={`${greeting}, ${firstName} 👋`}
        subtitle="Oto przegląd Twoich spraw"
        action={{ label: 'Dodaj dokument', href: '/documents/upload', icon: <Upload size={15} /> }}
      />

      {/* Stats row */}
      <section className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatsCard
          title="Dokumenty"
          value={s.total_documents}
          icon={FileStack}
          accentColor="var(--color-info)"
          accentDim="var(--color-info-dim)"
          delay={0}
        />
        <StatsCard
          title="Pilne terminy"
          value={s.urgent_deadlines}
          icon={AlertTriangle}
          accentColor={s.urgent_deadlines > 0 ? 'var(--color-danger)' : 'var(--color-success)'}
          accentDim={s.urgent_deadlines > 0 ? 'var(--color-danger-dim)' : 'var(--color-success-dim)'}
          badge={s.urgent_deadlines > 0 ? 'UWAGA' : 'OK'}
          badgeColor={s.urgent_deadlines > 0 ? 'var(--color-danger)' : 'var(--color-success)'}
          delay={100}
        />
        <StatsCard
          title="Aktywne rachunki"
          value={s.active_bills}
          icon={CreditCard}
          accentColor="var(--color-purple)"
          accentDim="var(--color-purple-dim)"
          delay={200}
        />
        <StatsCard
          title="Wygenerowane pisma"
          value={s.total_letters}
          icon={ScrollText}
          accentColor="var(--color-amber)"
          accentDim="var(--color-amber-dim)"
          delay={300}
        />
      </section>

      {/* Main grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">

        {/* Left column (2/3) */}
        <div className="lg:col-span-2 space-y-6">

          {/* Quick actions */}
          <section className="animate-fade-in-up delay-200">
            <SectionHeader
              title="Szybkie akcje"
              subtitle="Co chcesz zrobić?"
            />
            <QuickActions />
          </section>

          {/* Urgent deadlines */}
          <section className="animate-fade-in-up delay-300">
            <SectionHeader
              title="Najbliższe terminy"
              subtitle={`${s.pending_deadlines} oczekujących`}
              link={{ label: 'Wszystkie', href: '/deadlines' }}
            />
            <UrgentDeadlines deadlines={deadlines} />
          </section>

          {/* AI tip of the day */}
          {s.total_documents === 0 && <OnboardingCard />}
        </div>

        {/* Right column (1/3) */}
        <div className="space-y-6">

          {/* Plan status */}
          <PlanWidget plan={dbUser.plan} aiCalls={dbUser.ai_calls_month} />

          {/* Recent activity */}
          <section className="animate-fade-in-up delay-400">
            <SectionHeader
              title="Ostatnia aktywność"
              subtitle="Historia działań"
            />
            <ActivityFeed items={activity as any[]} />
          </section>
        </div>
      </div>
    </>
  )
}

// ──────────────────────────────────────────────
// Sub-components (server)

function SectionHeader({
  title,
  subtitle,
  link,
}: {
  title: string
  subtitle?: string
  link?: { label: string; href: string }
}) {
  return (
    <div className="flex items-baseline justify-between mb-3">
      <div>
        <h2 className="font-display font-semibold text-primary" style={{ fontSize: '15px' }}>
          {title}
        </h2>
        {subtitle && (
          <p className="text-xs text-muted mt-0.5">{subtitle}</p>
        )}
      </div>
      {link && (
        <a
          href={link.href}
          className="text-xs font-medium hover:underline"
          style={{ color: 'var(--color-amber)' }}
        >
          {link.label} →
        </a>
      )}
    </div>
  )
}

function PlanWidget({ plan, aiCalls }: { plan: string; aiCalls: number }) {
  const isFree = plan === 'free'
  const limit = isFree ? 5 : 999
  const pct = isFree ? Math.min((aiCalls / limit) * 100, 100) : 0

  return (
    <div
      className="card p-4 animate-fade-in-up delay-200"
      style={{
        background: 'linear-gradient(135deg, var(--color-elevated), rgba(232,160,32,0.03))',
      }}
    >
      <div className="flex items-center justify-between mb-3">
        <div>
          <span
            className="badge"
            style={{
              background: isFree ? 'var(--color-border)' : 'var(--color-amber-dim)',
              color: isFree ? 'var(--color-secondary)' : 'var(--color-amber)',
            }}
          >
            {isFree ? 'FREE' : '⭐ PREMIUM'}
          </span>
        </div>
        {isFree && (
          <a
            href="/settings/billing"
            className="text-xs font-semibold"
            style={{ color: 'var(--color-amber)' }}
          >
            Upgrade →
          </a>
        )}
      </div>

      <div className="mb-1 flex items-center justify-between">
        <p className="text-xs text-secondary font-medium">
          <Sparkles size={11} className="inline mr-1" style={{ color: 'var(--color-amber)' }} />
          Analizy AI w tym miesiącu
        </p>
        <p className="text-xs font-semibold text-primary">
          {aiCalls} / {isFree ? limit : '∞'}
        </p>
      </div>

      {isFree && (
        <>
          <div
            className="w-full h-1.5 rounded-full overflow-hidden"
            style={{ background: 'var(--color-border)' }}
          >
            <div
              className="h-full rounded-full transition-all"
              style={{
                width: `${pct}%`,
                background: pct >= 80
                  ? 'var(--color-danger)'
                  : pct >= 60
                    ? 'var(--color-warning)'
                    : 'var(--color-amber)',
              }}
            />
          </div>
          {pct >= 80 && (
            <p className="text-xs mt-1.5" style={{ color: 'var(--color-danger)' }}>
              Zbliżasz się do limitu
            </p>
          )}
        </>
      )}
    </div>
  )
}

function OnboardingCard() {
  return (
    <div
      className="card p-5 animate-fade-in-up delay-400"
      style={{
        background: 'linear-gradient(135deg, rgba(59,130,246,0.05), var(--color-elevated))',
        border: '1px solid var(--color-info-dim)',
      }}
    >
      <div
        className="w-10 h-10 rounded-xl flex items-center justify-center mb-3"
        style={{ background: 'var(--color-info-dim)' }}
      >
        <Sparkles size={20} style={{ color: 'var(--color-info)' }} />
      </div>
      <h3 className="font-display font-semibold text-primary text-sm mb-1">
        Zacznij od dodania dokumentu
      </h3>
      <p className="text-xs text-secondary leading-relaxed mb-4">
        Wgraj fakturę, pismo urzędowe lub umowę. AI automatycznie je przeanalizuje,
        wyciągnie terminy i zaproponuje akcje.
      </p>
      <a href="/documents/upload" className="btn-amber text-sm">
        <Upload size={14} />
        Wgraj pierwszy dokument
      </a>
    </div>
  )
}
