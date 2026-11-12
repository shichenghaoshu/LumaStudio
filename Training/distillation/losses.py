"""Losses use only completion tokens; cross-tokenizer logit distillation is rejected."""
import torch
import torch.nn.functional as F

def masked_logit_distillation(student_logits, teacher_logits, labels, temperature=2.0):
    if student_logits.shape != teacher_logits.shape:
        raise ValueError("Logit distillation requires aligned sequence and vocabulary dimensions")
    if temperature <= 0:
        raise ValueError("Temperature must be positive")
    mask = labels[:, 1:] != -100
    if not mask.any():
        raise ValueError("No completion tokens to distill")
    student = F.log_softmax(student_logits[:, :-1].float() / temperature, dim=-1)
    teacher = F.softmax(teacher_logits[:, :-1].float() / temperature, dim=-1)
    divergences = F.kl_div(student, teacher, reduction="none").sum(-1)
    return divergences[mask].mean() * temperature * temperature

class FeatureProjection(torch.nn.Module):
    def __init__(self, student_width, teacher_width):
        super().__init__()
        self.projection = torch.nn.Linear(student_width, teacher_width, bias=False)

    def forward(self, student, teacher, labels):
        mask = labels != -100
        if not mask.any():
            raise ValueError("No completion features to distill")
        projected = self.projection(student.float())
        return (1 - F.cosine_similarity(projected[mask], teacher.detach().float()[mask], dim=-1)).mean()
