import { useState, useEffect, lazy, Suspense } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { supabase } from './supabase'
import './App.css'

const LandingPage = lazy(() => import('./LandingPage'))
const LoginPage   = lazy(() => import('./LoginPage'))
const HomePage    = lazy(() => import('./HomePage'))
const HoursBoard  = lazy(() => import('./HoursBoard'))
const CheckinPage = lazy(() => import('./CheckinPage'))

const Splash = () => (
  <div className="splash">
    <div className="logo">5669</div>
  </div>
)

export default function App() {
  const [session, setSession] = useState(undefined)
  const [roles, setRoles]     = useState([])

  useEffect(() => {
    async function loadRoles(userId) {
      const { data } = await supabase
        .from('member_roles')
        .select('role')
        .eq('member_id', userId)
      setRoles(data?.map(r => r.role) ?? [])
    }

    supabase.auth.getSession()
      .then(({ data: { session } }) => {
        setSession(session)
        if (session) loadRoles(session.user.id)
      })
      .catch(() => setSession(null))

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session)
      if (session) loadRoles(session.user.id)
      else setRoles([])
    })
    return () => subscription.unsubscribe()
  }, [])

  // Hold until auth is resolved so we never flash the wrong route
  if (session === undefined) return <Splash />

  const hasRole = (r) => roles.includes(r)

  return (
    <Suspense fallback={<Splash />}>
      <Routes>
        {/* ── Public ─────────────────────────────────────────── */}
        <Route
          path="/"
          element={session ? <Navigate to="/dashboard" replace /> : <LandingPage />}
        />
        <Route
          path="/login"
          element={session ? <Navigate to="/dashboard" replace /> : <LoginPage />}
        />

        {/* ── Protected ──────────────────────────────────────── */}
        <Route
          path="/dashboard"
          element={session
            ? <HomePage session={session} hasRole={hasRole} />
            : <Navigate to="/login" replace />}
        />
        <Route
          path="/hours"
          element={session
            ? <HoursBoard />
            : <Navigate to="/login" replace />}
        />
        <Route
          path="/checkin"
          element={session
            ? <CheckinPage session={session} />
            : <Navigate to="/" replace />}
        />

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Suspense>
  )
}
