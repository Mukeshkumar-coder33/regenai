import * as React from 'react';
import { Slot } from '@radix-ui/react-slot';
import { cva } from 'class-variance-authority';

import { cn } from '@/lib/utils';

const badgeVariants = cva(
    'inline-flex items-center justify-center rounded-md border px-2 py-0.5 text-xs font-semibold w-fit whitespace-nowrap shrink-0 [&>svg]:size-3 gap-1 [&>svg]:pointer-events-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px] aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive transition-[color,box-shadow] overflow-hidden',
    {
        variants: {
            variant: {
                default: 'border-[#C9DED1] bg-[#E8F3EC] text-[#087A4B] [a&]:hover:bg-[#E8F3EC]/80',
                secondary: 'border-[#E1E8E4] bg-[#EFF3F1] text-[#17231F] [a&]:hover:bg-[#EFF3F1]/80',
                destructive:
                    'border-[#F8B4B4] bg-[#FDE8E8] text-[#DC4C4C] [a&]:hover:bg-[#FDE8E8]/80',
                outline: 'border-[#E1E8E4] bg-white text-[#17231F] [a&]:hover:bg-[#F1F7F3] [a&]:hover:text-[#087A4B]',
                success: 'border-[#C9DED1] bg-[#E8F3EC] text-[#16834A]',
                warning: 'border-[#FDE68A] bg-[#FEF3C7] text-[#E7A52B]',
            }
        },
        defaultVariants: {
            variant: 'default'
        }
    }
);

function Badge({
    className,
    variant,
    asChild = false,
    ...props
}) {
    const Comp = asChild ? Slot : 'span';

    return <Comp data-slot="badge" className={cn(badgeVariants({ variant }), className)} {...props} />;
}

export { Badge, badgeVariants };
