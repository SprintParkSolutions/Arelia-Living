import { LightningElement } from "lwc";

const SVG = {
  MapPin: `<svg viewBox="0 0 24 24" width="20" height="20" fill="none"><path d="M12 21s6-5.433 6-10A6 6 0 0 0 6 11c0 4.567 6 10 6 10z" stroke="currentColor" stroke-width="1.4"/><circle cx="12" cy="11" r="2.5" fill="currentColor"/></svg>`,
  Phone: `<svg viewBox="0 0 24 24" width="20" height="20" fill="none"><path d="M22 16.92v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 3 5.18 2 2 0 0 1 5 3h3a2 2 0 0 1 2 1.72l.76 2.56a2 2 0 0 1-.45 2.11L9.9 10.1a16 16 0 0 0 4 4l1.7-1.7a2 2 0 0 1 2.11-.45l2.56.76A2 2 0 0 1 22 16.92z" stroke="currentColor" stroke-width="1.4"/></svg>`,
  Mail: `<svg viewBox="0 0 24 24" width="20" height="20" fill="none"><rect x="3" y="5" width="18" height="14" rx="2" stroke="currentColor" stroke-width="1.4"/><polyline points="3,7 12,13 21,7" stroke="currentColor" stroke-width="1.4" fill="none"/></svg>`,
  Clock: `<svg viewBox="0 0 24 24" width="20" height="20" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.4"/><path d="M12 7v6l4 2" stroke="currentColor" stroke-width="1.4"/></svg>`,
  Instagram: `<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><rect x="3" y="3" width="18" height="18" rx="5"/></svg>`,
  Facebook: `<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M22 12a10 10 0 1 0-11.5 9.9v-7H8.1V12h2.4V9.7c0-2.4 1.4-3.8 3.6-3.8h2v2.2h-1.1c-1.1 0-1.4.7-1.4 1.4V12h2.4l-.4 2.9h-2V22A10 10 0 0 0 22 12z"/></svg>`,
  Linkedin: `<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M4.98 3.5a2.5 2.5 0 1 1 .02 0zM3 8.98h3.96V21H3V8.98zM9.5 8.98H13v1.6h.06c.47-.9 1.62-1.86 3.34-1.86 3.56 0 4.2 2.34 4.2 5.38V21H17.2v-5.2c0-1.24-.02-2.84-1.72-2.84-1.72 0-1.98 1.34-1.98 2.74V21H9.5z"/></svg>`
};

export default class ContactSection extends LightningElement {
  contactDetails = [
    {
      title: "Visit Our Studio",
      svg: SVG.MapPin,
      lines: ["123 Design Avenue, Suite 400", "New York, NY 10001"]
    },
    {
      title: "Call Us",
      svg: SVG.Phone,
      lines: ["+1 (234) 567-890", "+1 (234) 567-891"]
    },
    {
      title: "Email Us",
      svg: SVG.Mail,
      lines: ["hello@luxeinteriors.com", "projects@luxeinteriors.com"]
    },
    {
      title: "Working Hours",
      svg: SVG.Clock,
      lines: ["Mon - Fri: 9:00 AM - 6:00 PM", "Sat: By Appointment"]
    }
  ];

  socialLinks = [
    { label: "Instagram", svg: SVG.Instagram, href: "https://instagram.com" },
    { label: "Facebook", svg: SVG.Facebook, href: "https://facebook.com" },
    { label: "LinkedIn", svg: SVG.Linkedin, href: "https://linkedin.com" }
  ];

  renderedCallback() {
    this.injectSVGs();
  }

  injectSVGs() {
    // Contact cards
    this.contactDetails.forEach((d) => {
      const target = this.template.querySelector(`span[data-key="${d.title}"]`);
      if (target) target.innerHTML = d.svg;
    });

    // Social icons
    this.socialLinks.forEach((s) => {
      const target = this.template.querySelector(`span[data-key="${s.label}"]`);
      if (target) target.innerHTML = s.svg;
    });
  }
}