'use client';

import * as React from 'react';
import * as TabsPrimitive from '@radix-ui/react-tabs';

import { cn } from '@/lib/utils';

function Tabs({ className, ...props }) {
    return <TabsPrimitive.Root data-slot="tabs" className={cn('flex flex-col gap-2', className)} {...props} />;
}

function TabsList({ className, ...props }) {
    return (
        <TabsPrimitive.List
            data-slot="tabs-list"
            className={cn(
                'bg-[#EFF3F1] text-[#52615B] inline-flex h-11 max-w-full overflow-x-auto no-scrollbar items-center justify-start sm:justify-center rounded-2xl p-1 border border-[#E1E8E4] gap-1',
                className
            )}
            {...props}
        />
    );
}

function TabsTrigger({ className, ...props }) {
    return (
        <TabsPrimitive.Trigger
            data-slot="tabs-trigger"
            className={cn(
                "data-[state=active]:bg-white data-[state=active]:text-[#087A4B] data-[state=active]:shadow-xs data-[state=active]:border data-[state=active]:border-[#E1E8E4] text-[#52615B] hover:text-[#17231F] hover:bg-[#E8F3EC] inline-flex h-full flex-1 items-center justify-center gap-2 rounded-xl px-4 py-1.5 text-xs sm:text-sm font-semibold whitespace-nowrap transition-all duration-150 outline-none focus-visible:ring-2 focus-visible:ring-[#087A4B]/30 disabled:pointer-events-none disabled:opacity-50 select-none cursor-pointer [&_svg]:size-4",
                className
            )}
            {...props}
        />
    );
}

function TabsContent({ className, ...props }) {
    return (
        <TabsPrimitive.Content data-slot="tabs-content" className={cn('flex-1 outline-none', className)} {...props} />
    );
}

export { Tabs, TabsList, TabsTrigger, TabsContent };
