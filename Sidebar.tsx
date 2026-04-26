'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { UserButton, useUser } from '@clerk/nextjs'
import {
  LayoutDashboard,
  FileStack,
  Sparkles,
  ScrollText,
  Calendar,
  CreditCard,
  Building2,
  Search,
  Settings,
  ChevronRight,
  Zap,
  Crown,
} from 'lucide-react'

const NAV_ITEMS = [
  {
    group: 'Główne',
    items: [
      { href: '/dashboard',   label: 'Dashboard',    icon: LayoutDashboard },
      { href: '/documents',   label: 'Dokumenty',    icon: FileStack },
      { href: '/analyzer',    label: 'Analizator AI', icon: Sparkles },
      { href: '/letters',     label: 'Generator pism', icon: ScrollText },
    ],
  },
  {
    group: 'Śledzenie',
    items: [
      { href: '/deadlines',   label: 'Terminy',      icon: Calendar },
      { href: '/bills',       label: 'Rachunki',     icon: CreditCard },
    ],
  },
  {
    group: 'Narzędzia',
    items: [
      { href: '/assistant',   label: 'Asystent urzędowy', icon: Building2 },
      { href: '/search',      label: 'Szukaj',        icon: Search },
    ],
  },
]

export default function Sidebar() {
  const pathname = usePathname()
  const { user } = useUser()

  const isPremium = false // TODO: get from user metadata

  return (
    <aside
      className="fixed left-0 top-0 h-screen flex flex-col z-40 scanlines"
      style={{
        width: 'var(--sidebar-width)',
        background: 'var(--color-surface)',
        borderRight: '1px solid var(--color-border)',
      }}
    >
      {/* Logo */}
      <div className="px-5 py-5" style={{ borderBottom: '1px solid var(--color-border)' }}>
        <Link href="/dashboard" className="flex items-center gap-2.5 group">
          <div
            className="w-8 h-8 rounded-lg flex items-center justify-center text-inverse font-bold text-sm"
            style={{ background: 'var(--color-amber)', fontFamily: 'var(--font-brand)' }}
          >
            LA
          </div>
          <div>
            <span className="font-brand text-primary font-bold text-base leading-none block">
              Life Admin
            </span>
            <span
              className="text-xs font-medium"
              style={{ color: 'var(--color-amber)', letterSpacing: '0.05em' }}
            >
              AI
            </span>
          </div>
        </Link>
      </div>

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto py-4 px-3">
        {NAV_ITEMS.map((group) => (
          <div key={group.group} className="mb-5">
            <p
              className="px-2 mb-1.5 text-xs font-semibold uppercase tracking-widest"
              style={{ color: 'var(--color-muted)', letterSpacing: '0.1em' }}
            >
              {group.group}
            </p>
            <ul className="space-y-0.5">
              {group.items.map(({ href, label, icon: Icon }) => {
                const isActive =
                  href === '/dashboard'
                    ? pathname === '/dashboard'
                    : pathname.startsWith(href)

                return (
                  <li key={href}>
                    <Link
                      href={href}
                      className="flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all duration-150 group relative"
                      style={{
                        background: isActive ? 'var(--color-amber-dim)' : 'transparent',
                        color: isActive ? 'var(--color-amber)' : 'var(--color-secondary)',
                      }}
                    >
                      {/* Active indicator */}
                      {isActive && (
                        <span
                          className="absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-5 rounded-r-full"
                          style={{ background: 'var(--color-amber)' }}
                        />
                      )}
                      <Icon
                        size={16}
                        strokeWidth={isActive ? 2.5 : 1.8}
                        style={{ color: isActive ? 'var(--color-amber)' : 'var(--color-muted)', flexShrink: 0 }}
                      />
                      <span className={isActive ? 'text-amber' : ''}>{label}</span>
                      {!isActive && (
                        <ChevronRight
                          size={12}
                          className="ml-auto opacity-0 group-hover:opacity-40 transition-opacity"
                        />
                      )}
                    </Link>
                  </li>
                )
              })}
            </ul>
          </div>
        ))}
      </nav>

      {/* Premium upsell (free users) */}
      {!isPremium && (
        <div className="px-3 pb-3">
          <div
            className="rounded-xl p-3 relative overflow-hidden"
            style={{
              background: 'linear-gradient(135deg, rgba(232,160,32,0.1), rgba(232,160,32,0.05))',
              border: '1px solid var(--color-amber-dim)',
            }}
          >
            <Crown size={16} className="text-amber mb-2" style={{ color: 'var(--color-amber)' }} />
            <p className="text-xs font-semibold text-primary mb-0.5">Przejdź na Premium</p>
            <p className="text-xs" style={{ color: 'var(--color-secondary)' }}>
              Unlimited AI, więcej dokumentów
            </p>
            <Link
              href="/settings/billing"
              className="mt-2 flex items-center gap-1.5 text-xs font-semibold"
              style={{ color: 'var(--color-amber)' }}
            >
              <Zap size={11} />
              Upgrade teraz
            </Link>
          </div>
        </div>
      )}

      {/* User section */}
      <div
        className="px-4 py-4 flex items-center gap-3"
        style={{ borderTop: '1px solid var(--color-border)' }}
      >
        <UserButton
          appearance={{
            elements: {
              avatarBox: 'w-8 h-8',
              userButtonPopoverCard: 'bg-surface border border-border',
            },
          }}
        />
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-primary truncate leading-tight">
            {user?.firstName ?? 'Użytkownik'}
          </p>
          <p
            className="text-xs truncate"
            style={{ color: 'var(--color-muted)' }}
          >
            {user?.primaryEmailAddress?.emailAddress ?? ''}
          </p>
        </div>
        <Link
          href="/settings"
          className="p-1.5 rounded-lg hover:bg-overlay transition-colors"
          style={{ color: 'var(--color-muted)' }}
        >
          <Settings size={14} />
        </Link>
      </div>
    </aside>
  )
}
