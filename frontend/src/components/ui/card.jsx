import * as React from 'react';

import { cn } from '@/lib/utils';

function Card({ className, ...props }) {
    return (
        <div
            data-slot="card"
            className={cn(
                'bg-white text-[#17231F] flex flex-col gap-3 sm:gap-6 rounded-xl sm:rounded-2xl border border-[#E1E8E4] py-3 sm:py-6 shadow-[0_1px_3px_0_rgba(23,35,31,0.04),0_1px_2px_-1px_rgba(23,35,31,0.04)] transition-shadow',
                className
            )}
            {...props}
        />
    );
}

function CardHeader({ className, ...props }) {
    return (
        <div
            data-slot="card-header"
            className={cn(
                '@container/card-header grid auto-rows-min grid-rows-[auto_auto] items-start gap-1 sm:gap-1.5 px-3.5 sm:px-6 has-data-[slot=card-action]:grid-cols-[1fr_auto] [.border-b]:pb-3 sm:[.border-b]:pb-6',
                className
            )}
            {...props}
        />
    );
}

function CardTitle({ className, ...props }) {
    return <div data-slot="card-title" className={cn('text-sm sm:text-base md:text-[18px] leading-snug font-semibold tracking-normal', className)} {...props} />;
}

function CardDescription({ className, ...props }) {
    return <div data-slot="card-description" className={cn('text-xs sm:text-sm text-muted-foreground leading-normal', className)} {...props} />;
}

function CardAction({ className, ...props }) {
    return (
        <div
            data-slot="card-action"
            className={cn('col-start-2 row-span-2 row-start-1 self-start justify-self-end', className)}
            {...props}
        />
    );
}

function CardContent({ className, ...props }) {
    return (
        <div
            data-slot="card-content"
            className={cn('px-3.5 sm:px-6 overflow-auto min-w-full', className)}
            {...props}
        />
    );
}

function CardFooter({ className, ...props }) {
    return (
        <div data-slot="card-footer" className={cn('flex items-center px-4 sm:px-6 [.border-t]:pt-4 sm:[.border-t]:pt-6', className)} {...props} />
    );
}

export { Card, CardHeader, CardFooter, CardTitle, CardAction, CardDescription, CardContent };
