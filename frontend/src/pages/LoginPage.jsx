import { useEffect, useState } from 'react';
import { useCustomAuth } from '../hooks/useCustomAuth';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { toast } from 'sonner';
import { Eye, EyeOff, Users, TrendingUp, Briefcase } from 'lucide-react';
import Footer from '../components/Footer';

export default function LoginPage({ resetToken: resetTokenProp }) {
  const { login, isLoggingIn } = useCustomAuth();
  
  // Login Form State
  const [loginUserId, setLoginUserId] = useState('');
  const [loginPassword, setLoginPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [mode, setMode] = useState('login');

  const [resetToken, setResetToken] = useState(resetTokenProp || '');
  const [resetNewPassword, setResetNewPassword] = useState('');
  const [resetConfirmPassword, setResetConfirmPassword] = useState('');
  const [isResetting, setIsResetting] = useState(false);

  useEffect(() => {
    const tokenFromUrl = new URLSearchParams(window.location.search).get('resetToken') || '';
    const token = resetTokenProp || tokenFromUrl;
    if (token) {
      setResetToken(token);
      setMode('reset');
    }
  }, [resetTokenProp]);

  const handleLogin = async (e) => {
    if (e) e.preventDefault();
    try {
      await login((loginUserId || '').trim(), (loginPassword || '').trim());
    } catch (error) {
      console.error("Login failed", error);
      const msg = String(error?.message || '').toLowerCase();
      if (msg.includes('maintenance') || msg.includes('failed to fetch')) {
        if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('server-maintenance'));
        return;
      }
      if (error.message === "The user is not found") {
        toast.error("The user is not found");
      } else {
        toast.error(error.message || "Login failed. Please check your credentials.");
      }
    }
  };

  const handleResetPassword = async (e) => {
    if (e) e.preventDefault();
    if (!resetToken) {
      toast.error('Reset token is missing');
      return;
    }
    if (!resetNewPassword || resetNewPassword.length < 4) {
      toast.error('Password must be at least 4 characters');
      return;
    }
    if (resetNewPassword !== resetConfirmPassword) {
      toast.error('Passwords do not match');
      return;
    }
    setIsResetting(true);
    try {
      const res = await fetch('/api/auth/reset-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: resetToken, newPassword: resetNewPassword })
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ message: 'Reset failed' }));
        throw new Error(err.message || 'Reset failed');
      }
      toast.success('Password reset successfully. Please login.');
      window.location.href = '/';
    } catch (e2) {
      toast.error(e2.message || 'Reset failed');
    } finally {
      setIsResetting(false);
    }
  };

  return (
    <div className="min-h-screen w-full bg-[#F5F7F6] text-[#17231F] flex overflow-x-hidden font-sans">
      {/* Left Hero Pane (Matching Design 3: Feature Highlight with Premium Emerald Theme) */}
      <div 
        className="hidden lg:flex lg:flex-1 relative p-10 xl:p-14 2xl:p-16 flex-col justify-between"
        style={{
          background: "linear-gradient(145deg, #06452F 0%, #07563B 50%, #087A4B 100%)"
        }}
      >
        {/* Brand Logo in top-left */}
        <div className="flex items-center">
          <img src="/regen-emblem.svg" alt="ReGen" className="w-[135px] xl:w-[145px] h-auto object-contain" />
        </div>

        {/* Hero Content */}
        <div className="my-auto max-w-xl xl:max-w-2xl">
          <h1 className="login-hero-heading text-[38px] lg:text-[54px] xl:text-[58px] font-extrabold tracking-tight text-white leading-[1.10] mb-5">
            A Better<br />
            Workplace<br />
            Starts Here
          </h1>
          <p className="login-hero-desc text-[18px] lg:text-[22px] xl:text-[24px] text-[#E8F3EC] font-normal leading-[1.5] mb-8 xl:mb-9">
            Seamless attendance.<br />
            Stronger teams.<br />
            Greater productivity.
          </p>

          {/* Three Feature Highlight Badges */}
          <div className="space-y-3.5 max-w-md">
            {/* Feature 1 */}
            <div className="flex items-center gap-4 p-3.5 rounded-2xl bg-[#07563B]/80 border border-[#087A4B]/50 backdrop-blur-md transition-all hover:border-[#E8F3EC]/50 shadow-sm">
              <div className="w-11 h-11 rounded-xl bg-[#E8F3EC]/15 border border-[#E8F3EC]/25 flex items-center justify-center shrink-0 text-[#E8F3EC]">
                <Users className="w-5 h-5" />
              </div>
              <div>
                <h3 className="text-sm font-semibold text-white leading-snug">Better Visibility</h3>
                <p className="text-xs text-[#E8F3EC]/85 mt-0.5">Track your workforce in real time</p>
              </div>
            </div>

            {/* Feature 2 */}
            <div className="flex items-center gap-4 p-3.5 rounded-2xl bg-[#07563B]/80 border border-[#087A4B]/50 backdrop-blur-md transition-all hover:border-[#E8F3EC]/50 shadow-sm">
              <div className="w-11 h-11 rounded-xl bg-[#E8F3EC]/15 border border-[#E8F3EC]/25 flex items-center justify-center shrink-0 text-[#E8F3EC]">
                <TrendingUp className="w-5 h-5" />
              </div>
              <div>
                <h3 className="text-sm font-semibold text-white leading-snug">Higher Productivity</h3>
                <p className="text-xs text-[#E8F3EC]/85 mt-0.5">Streamline daily operations</p>
              </div>
            </div>

            {/* Feature 3 */}
            <div className="flex items-center gap-4 p-3.5 rounded-2xl bg-[#07563B]/80 border border-[#087A4B]/50 backdrop-blur-md transition-all hover:border-[#E8F3EC]/50 shadow-sm">
              <div className="w-11 h-11 rounded-xl bg-[#E8F3EC]/15 border border-[#E8F3EC]/25 flex items-center justify-center shrink-0 text-[#E8F3EC]">
                <Briefcase className="w-5 h-5" />
              </div>
              <div>
                <h3 className="text-sm font-semibold text-white leading-snug">Simpler Management</h3>
                <p className="text-xs text-[#E8F3EC]/85 mt-0.5">Everything in one place</p>
              </div>
            </div>
          </div>
        </div>

        <div className="text-xs text-[#E8F3EC]/70">
          © {new Date().getFullYear()} ReGen Innovations Inc. All rights reserved.
        </div>
      </div>

      {/* Right Login Pane */}
      <div className="flex-1 flex flex-col items-center justify-center p-3.5 sm:p-8 lg:p-10 min-h-screen min-h-[100dvh] py-6 sm:py-10 relative bg-[#F5F7F6] overflow-y-auto">
        {/* Ambient Soft Mint Glow */}
        <div className="absolute top-1/4 right-1/4 w-72 sm:w-96 h-72 sm:h-96 bg-[#087A4B]/5 rounded-full blur-[100px] pointer-events-none" />

        {/* Floating Login Card */}
        <div className="w-full max-w-md my-auto bg-white border border-[#E1E8E4] shadow-[0_20px_50px_-15px_rgba(23,35,31,0.08)] rounded-2xl sm:rounded-3xl p-5 sm:p-8 md:p-10 relative z-10 transition-all">
          {/* Header */}
          <div className="flex flex-col items-center text-center">
            {/* Centered ReGen Emblem */}
            <div className="flex justify-center mb-4">
              <img
                src="/regen-emblem.svg"
                alt="ReGen"
                className="h-12 w-auto object-contain"
              />
            </div>
            <h2 className="text-2xl font-bold tracking-tight text-[#17231F] mb-1.5">Login to ReGen</h2>
            <p className="text-xs sm:text-sm text-[#52615B] mb-6">
              Access your ReGen account.
            </p>
          </div>

          {mode === 'login' ? (
            <div className="space-y-4">
              <form onSubmit={handleLogin} className="space-y-4">
                <div className="space-y-1.5 text-left">
                  <Label htmlFor="loginUserId" className="text-xs font-semibold uppercase tracking-wider text-[#52615B]">
                    User ID
                  </Label>
                  <Input 
                    id="loginUserId" 
                    value={loginUserId} 
                    onChange={(e) => setLoginUserId(e.target.value)} 
                    required 
                    placeholder="Enter your user ID" 
                    className="h-11 bg-[#F8FAF9] border-[#E1E8E4] text-[#17231F] placeholder:text-[#829089] rounded-xl focus-visible:ring-2 focus-visible:ring-[#087A4B]/20 focus-visible:border-[#087A4B] focus-visible:bg-white"
                  />
                </div>

                <div className="space-y-1.5 text-left">
                  <Label htmlFor="loginPassword" className="text-xs font-semibold uppercase tracking-wider text-[#52615B]">
                    Password
                  </Label>
                  <div className="relative">
                    <Input 
                      id="loginPassword" 
                      type={showPassword ? "text" : "password"} 
                      value={loginPassword} 
                      onChange={(e) => setLoginPassword(e.target.value)} 
                      required 
                      placeholder="Enter your password" 
                      className="h-11 pr-10 bg-[#F8FAF9] border-[#E1E8E4] text-[#17231F] placeholder:text-[#829089] rounded-xl focus-visible:ring-2 focus-visible:ring-[#087A4B]/20 focus-visible:border-[#087A4B] focus-visible:bg-white"
                    />
                    <button
                      type="button"
                      tabIndex={-1}
                      onClick={() => setShowPassword(prev => !prev)}
                      className="absolute right-3 top-1/2 -translate-y-1/2 text-[#829089] hover:text-[#087A4B] transition-colors"
                      title={showPassword ? "Hide password" : "Show password"}
                    >
                      {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                  </div>
                </div>

                <Button
                  type="submit"
                  disabled={isLoggingIn}
                  className="w-full h-11 text-sm font-semibold rounded-xl bg-[#087A4B] hover:bg-[#07563B] active:bg-[#06452F] text-white shadow-[0_4px_16px_rgba(8,122,75,0.25)] transition-all flex items-center justify-center gap-2 mt-2 cursor-pointer"
                >
                  {isLoggingIn ? (
                    <span className="flex items-center gap-2">
                      <span className="h-4 w-4 border-2 border-white/50 border-t-white rounded-full animate-spin" />
                      Verifying...
                    </span>
                  ) : (
                    "Login"
                  )} 
                </Button>
              </form>

              <div className="pt-4 text-center text-[11px] text-[#829089]">
                Made with <span className="text-red-500">❤️</span> by Krishub
              </div>
            </div>
          ) : (
            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-[#F8FAF9] border border-[#E1E8E4]">
                <h3 className="text-sm font-semibold text-[#17231F] mb-1">Reset Password</h3>
                <p className="text-xs text-[#52615B]">Open the link from admin/owner or paste token below.</p>
              </div>

              <form onSubmit={handleResetPassword} className="space-y-3.5">
                <div className="space-y-1.5 text-left">
                  <Label htmlFor="resetToken" className="text-xs font-semibold uppercase tracking-wider text-[#52615B]">
                    Reset Token
                  </Label>
                  <Input
                    id="resetToken"
                    name="resetToken"
                    value={resetToken}
                    onChange={(e) => setResetToken(e.target.value)}
                    placeholder="Paste reset token"
                    className="h-10 bg-[#F8FAF9] border-[#E1E8E4] text-[#17231F] placeholder:text-[#829089] rounded-xl text-xs focus-visible:ring-2 focus-visible:ring-[#087A4B]/20 focus-visible:border-[#087A4B] focus-visible:bg-white"
                    autoComplete="off"
                  />
                </div>

                <div className="space-y-1.5 text-left">
                  <Label htmlFor="resetNewPassword" className="text-xs font-semibold uppercase tracking-wider text-[#52615B]">
                    New Password
                  </Label>
                  <Input
                    id="resetNewPassword"
                    name="newPassword"
                    type="password"
                    value={resetNewPassword}
                    onChange={(e) => setResetNewPassword(e.target.value)}
                    placeholder="Enter new password"
                    className="h-10 bg-[#F8FAF9] border-[#E1E8E4] text-[#17231F] placeholder:text-[#829089] rounded-xl text-xs focus-visible:ring-2 focus-visible:ring-[#087A4B]/20 focus-visible:border-[#087A4B] focus-visible:bg-white"
                    autoComplete="new-password"
                  />
                </div>

                <div className="space-y-1.5 text-left">
                  <Label htmlFor="resetConfirmPassword" className="text-xs font-semibold uppercase tracking-wider text-[#52615B]">
                    Confirm Password
                  </Label>
                  <Input
                    id="resetConfirmPassword"
                    name="confirmPassword"
                    type="password"
                    value={resetConfirmPassword}
                    onChange={(e) => setResetConfirmPassword(e.target.value)}
                    placeholder="Re-enter new password"
                    className="h-10 bg-[#F8FAF9] border-[#E1E8E4] text-[#17231F] placeholder:text-[#829089] rounded-xl text-xs focus-visible:ring-2 focus-visible:ring-[#087A4B]/20 focus-visible:border-[#087A4B] focus-visible:bg-white"
                    autoComplete="new-password"
                  />
                </div>

                <Button 
                  type="submit" 
                  className="w-full h-11 text-sm font-semibold rounded-xl bg-[#087A4B] hover:bg-[#07563B] active:bg-[#06452F] text-white shadow-sm mt-2 cursor-pointer" 
                  disabled={isResetting}
                >
                  {isResetting ? 'Resetting...' : 'Reset Password'}
                </Button>
              </form>

              <Button 
                variant="outline" 
                className="w-full h-10 rounded-xl bg-white hover:bg-[#F1F7F3] border-[#E1E8E4] text-[#17231F] hover:text-[#087A4B] text-xs font-medium cursor-pointer" 
                onClick={() => setMode('login')}
              >
                Back to Login
              </Button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
