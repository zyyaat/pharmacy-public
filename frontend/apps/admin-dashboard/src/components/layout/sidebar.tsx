"use client";

import React, { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import {
  LayoutDashboard,
  Building2,
  Users,
  Shield,
  CreditCard,
  Settings,
  ChevronLeft,
  ChevronRight,
  Store,
  LogOut,
  Menu,
  X,
} from "lucide-react";
import { Button } from "@/components/ui";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";

interface SidebarItem {
  title: string;
  href: string;
  icon: React.ReactNode;
  badge?: string | number;
}

const sidebarItems: SidebarItem[] = [
  {
    title: "لوحة التحكم",
    href: "/",
    icon: <LayoutDashboard className="h-5 w-5" />,
  },
  {
    title: "الشركات",
    href: "/companies",
    icon: <Building2 className="h-5 w-5" />,
    badge: "12",
  },
  {
    title: "المستخدمين",
    href: "/users",
    icon: <Users className="h-5 w-5" />,
    badge: "48",
  },
  {
    title: "الصلاحيات",
    href: "/permissions",
    icon: <Shield className="h-5 w-5" />,
  },
  {
    title: "الحسابات",
    href: "/accounts",
    icon: <CreditCard className="h-5 w-5" />,
  },
  {
    title: "الصيدليات",
    href: "/pharmacies",
    icon: <Store className="h-5 w-5" />,
  },
];

const bottomItems: SidebarItem[] = [
  {
    title: "الإعدادات",
    href: "/settings",
    icon: <Settings className="h-5 w-5" />,
  },
];

interface SidebarProps {
  className?: string;
  mobileOpen?: boolean;
  onMobileClose?: () => void;
}

export function Sidebar({ className, mobileOpen: controlledMobileOpen, onMobileClose }: SidebarProps) {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);
  const [internalMobileOpen, setInternalMobileOpen] = useState(false);
  
  // Use controlled or uncontrolled mode
  const mobileOpen = controlledMobileOpen !== undefined ? controlledMobileOpen : internalMobileOpen;
  const handleMobileClose = onMobileClose || (() => setInternalMobileOpen(false));
  const handleMobileOpen = () => {
    if (onMobileClose) {
      // Controlled mode - parent should handle opening
      // We'll expose this via a ref or just let parent handle it
    } else {
      setInternalMobileOpen(true);
    }
  };

  const SidebarContent = (
    <div
      className={cn(
        "flex h-full flex-col bg-card border-l border-border transition-all duration-300",
        collapsed ? "w-[70px]" : "w-[260px]",
        className
      )}
    >
      {/* Logo */}
      <div className="flex h-16 items-center justify-between border-b border-border px-4">
        {!collapsed && (
          <Link href="/" className="flex items-center gap-2">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary text-primary-foreground font-bold">
              P
            </div>
            <span className="text-lg font-bold gradient-text">Pharmacy OS</span>
          </Link>
        )}
        {collapsed && (
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary text-primary-foreground font-bold mx-auto">
            P
          </div>
        )}
        
        {/* Mobile Close Button */}
        <button
          className="lg:hidden p-1.5 rounded-lg hover:bg-accent"
          onClick={handleMobileClose}
        >
          <X className="h-5 w-5" />
        </button>

        {/* Desktop Collapse Button */}
        <button
          className="hidden lg:flex p-1.5 rounded-lg hover:bg-accent"
          onClick={() => setCollapsed(!collapsed)}
        >
          {collapsed ? (
            <ChevronLeft className="h-4 w-4" />
          ) : (
            <ChevronRight className="h-4 w-4" />
          )}
        </button>
      </div>

      {/* Navigation */}
      <nav className="flex-1 space-y-1 p-3 overflow-y-auto">
        <div className="space-y-1">
          {sidebarItems.map((item) => {
            const isActive = pathname === item.href || 
              (item.href !== "/" && pathname.startsWith(item.href));
            
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={handleMobileClose}
                className={cn(
                  "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-all duration-200 group relative",
                  isActive
                    ? "bg-primary/10 text-primary"
                    : "text-muted-foreground hover:bg-accent hover:text-foreground"
                )}
              >
                {isActive && (
                  <div className="absolute right-0 top-1/2 -translate-y-1/2 w-1 h-8 bg-primary rounded-l-full" />
                )}
                <span className={cn("transition-colors", isActive && "text-primary")}>
                  {item.icon}
                </span>
                {!collapsed && (
                  <>
                    <span className="flex-1">{item.title}</span>
                    {item.badge && (
                      <span className={cn(
                        "px-2 py-0.5 text-xs rounded-full",
                        isActive ? "bg-primary/20 text-primary" : "bg-muted text-muted-foreground"
                      )}>
                        {item.badge}
                      </span>
                    )}
                  </>
                )}
                {collapsed && (
                  <div className="absolute right-full mr-2 hidden group-hover:block z-50">
                    <div className="bg-popover border border-border rounded-lg shadow-lg px-3 py-2 text-sm whitespace-nowrap">
                      {item.title}
                    </div>
                  </div>
                )}
              </Link>
            );
          })}
        </div>

        {/* Bottom Items */}
        <div className="pt-4 mt-4 border-t border-border space-y-1">
          {bottomItems.map((item) => {
            const isActive = pathname === item.href ||
              (item.href !== "/" && pathname.startsWith(item.href));
            
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={handleMobileClose}
                className={cn(
                  "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-all duration-200 group",
                  isActive
                    ? "bg-primary/10 text-primary"
                    : "text-muted-foreground hover:bg-accent hover:text-foreground"
                )}
              >
                <span className={cn(isActive && "text-primary")}>{item.icon}</span>
                {!collapsed && <span>{item.title}</span>}
                {collapsed && (
                  <div className="absolute right-full mr-2 hidden group-hover:block z-50">
                    <div className="bg-popover border border-border rounded-lg shadow-lg px-3 py-2 text-sm whitespace-nowrap">
                      {item.title}
                    </div>
                  </div>
                )}
              </Link>
            );
          })}
        </div>
      </nav>

      {/* User Section */}
      <div className="border-t border-border p-4">
        <div className={cn(
          "flex items-center gap-3",
          collapsed ? "justify-center" : ""
        )}>
          <Avatar className="h-9 w-9">
            <AvatarImage src="/avatar.png" alt="User" />
            <AvatarFallback className="bg-primary/10 text-primary text-sm">
              م
            </AvatarFallback>
          </Avatar>
          {!collapsed && (
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium truncate">مدير النظام</p>
              <p className="text-xs text-muted-foreground truncate">admin@pharmacy.os</p>
            </div>
          )}
          {!collapsed && (
            <Button variant="ghost" size="icon" className="shrink-0 text-muted-foreground hover:text-destructive">
              <LogOut className="h-4 w-4" />
            </Button>
          )}
        </div>
      </div>
    </div>
  );

  return (
    <>
      {/* Mobile Overlay */}
      {mobileOpen && (
        <div
          className="fixed inset-0 bg-black/50 z-40 lg:hidden"
          onClick={handleMobileClose}
        />
      )}

      {/* Mobile Sidebar */}
      <aside className={cn(
        "fixed right-0 top-0 bottom-0 z-50 lg:hidden transition-transform duration-300",
        mobileOpen ? "translate-x-0" : "translate-x-full"
      )}>
        {SidebarContent}
      </aside>

      {/* Desktop Sidebar */}
      <aside className="hidden lg:block h-screen sticky top-0">
        {SidebarContent}
      </aside>
    </>
  );
}
