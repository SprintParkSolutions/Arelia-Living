import { LightningElement } from 'lwc';

export default class IdcCountingComponent extends LightningElement {
     startCount(event) {
        const target = event.currentTarget.querySelector('.count');
        const targetValue = parseFloat(target.getAttribute('data-target'));

        let count = 0;
        const isDecimal = targetValue % 1 !== 0;
        const increment = isDecimal ? 0.1 : Math.ceil(targetValue / 100);

        const updateCount = () => {
            if (count < targetValue) {
                count += increment;
                if (isDecimal) {
                    target.innerText = count.toFixed(1);
                } else {
                    target.innerText = count;
                }
                setTimeout(updateCount, 20);
            } else {
                target.innerText = isDecimal ? targetValue.toFixed(1) : targetValue;
            }
        };

        updateCount();
    }
}