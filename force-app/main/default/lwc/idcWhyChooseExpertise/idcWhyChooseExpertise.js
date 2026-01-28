import { LightningElement } from 'lwc';

export default class IdcWhyChooseExpertise extends LightningElement {
    benefits = [
        {
            id: 1,
            title: 'CREATIVE EXPERTISE',
            description:
                'We bring innovation and function together to match your vision and needs.',
            icon: '🎨'
        },
        {
            id: 2,
            title: 'PREMIUM QUALITY',
            description:
                'We use eco-friendly, high-quality materials for lasting elegance.',
            icon: '✔️'
        },
        {
            id: 3,
            title: 'ON-TIME DELIVERY',
            description:
                'We stay on schedule without compromising quality or design excellence.',
            icon: '➡️'
        },
        {
            id: 4,
            title: 'CLIENT FOCUS',
            description:
                'Your ideas come first – we shape our designs around what matters to you.',
            icon: '👤'
        },
        {
            id: 5,
            title: 'TRUSTED PROFESSIONALS',
            description:
                'A team of qualified designers with a proven track record of excellence.',
            icon: '⭐'
        }
    ];

    hasObserved = false;

    renderedCallback() {
        if (this.hasObserved) return;
        this.hasObserved = true;

        const cards = this.template.querySelectorAll('.hex-card');
        if (!cards || cards.length === 0) {
            return;
        }

        // Reveal animation on scroll
        const observer = new IntersectionObserver(
            entries => {
                entries.forEach(entry => {
                    if (entry.isIntersecting) {
                        entry.target.classList.add('show');
                        observer.unobserve(entry.target);
                    }
                });
            },
            {
                threshold: 0.2
            }
        );

        cards.forEach((card, index) => {
            // add a custom property for staggered delay
            card.style.setProperty('--delay', `${index * 0.12}s`);
            observer.observe(card);
        });
    }
}