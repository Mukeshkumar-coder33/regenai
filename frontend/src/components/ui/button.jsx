import * as React from 'react';
import { Slot } from '@radix-ui/react-slot';
import { cva } from 'class-variance-authority';

import { cn } from '@/lib/utils';

const buttonVariants = cva(
    "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-xl text-sm font-semibold transition-all duration-150 disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4 [&_svg]:shrink-0 outline-none focus-visible:border-ring focus-visible:ring-ring/40 focus-visible:ring-2 active:scale-[0.98] aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive select-none cursor-pointer max-w-full",
    {
        variants: {
            variant: {
                default: 'bg-[#087A4B] text-white shadow-xs hover:bg-[#07563B] active:bg-[#06452F] hover:shadow-sm focus-visible:ring-[#087A4B]/40',
                destructive:
                    'bg-[#DC4C4C] text-white shadow-xs hover:bg-[#C53B3B] focus-visible:ring-[#DC4C4C]/30',
                outline:
                    'border border-[#E1E8E4] bg-white shadow-2xs hover:bg-[#F1F7F3] hover:border-[#087A4B] hover:text-[#087A4B] text-[#17231F]',
                secondary: 'bg-white text-[#17231F] shadow-2xs hover:bg-[#F1F7F3] hover:text-[#087A4B] border border-[#E1E8E4]',
                ghost: 'hover:bg-[#E8F3EC] hover:text-[#087A4B] text-[#17231F]',
                link: 'text-[#087A4B] underline-offset-4 hover:underline hover:text-[#07563B]'
            },
            size: {
                default: 'h-9 sm:h-10 lg:h-10.5 px-3.5 sm:px-4.5 lg:px-5 py-2 text-xs sm:text-sm font-medium has-[>svg]:px-3 sm:has-[>svg]:px-3.5 lg:has-[>svg]:px-4',
                sm: 'h-8 sm:h-8.5 lg:h-9 rounded-lg sm:rounded-xl gap-1.5 px-2.5 sm:px-3 lg:px-3.5 text-xs sm:text-xs lg:text-sm font-medium has-[>svg]:px-2 sm:has-[>svg]:px-2.5',
                lg: 'h-10 sm:h-11 lg:h-12 rounded-xl sm:rounded-2xl px-4.5 sm:px-6 lg:px-7 text-sm sm:text-base font-semibold sm:font-bold has-[>svg]:px-3.5 sm:has-[>svg]:px-4.5',
                icon: 'size-8.5 sm:size-9 lg:size-10 rounded-xl hover:border-teal-500/40'
            }
        },
        defaultVariants: {
            variant: 'default',
            size: 'default'
        }
    }
);

function Button({
    className,
    variant,
    size,
    asChild = false,
    ...props
}) {
    const Comp = asChild ? Slot : 'button';

    return <Comp data-slot="button" className={cn(buttonVariants({ variant, size, className }))} {...props} />;
}

export { Button, buttonVariants };
